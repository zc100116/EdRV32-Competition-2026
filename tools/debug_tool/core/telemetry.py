"""telemetry.py — B2 design 3.5 v1 records and DDR measurements.

Host clock domain; wire fields are little endian, 320 bytes per record.
CSV preserves every raw field so replay uses the same measurement path.
"""

from collections import deque
import csv
import io
from pathlib import Path
import struct
import threading

RECORD_BYTES = 320
PORTS = ('P0 DISP', 'P1 VIN', 'P2 CPU', 'P3 NPU', 'P4 RND', 'P5 GEO', 'P6 ETH')
PORT_FIELDS = ('rd_txn', 'rd_beat', 'wr_txn', 'wr_beat', 'wait_sum', 'wait_max', 'urg_cnt')
TAIL_FIELDS = ('vin_ch0_frames', 'vin_ch2_frames', 'vin_ch0_overflow',
               'vin_ch2_overflow', 'disp_underflow', 'disp_frames', 'npu_completed',
               'npu_cycles', 'post_cycles', 'boxes', 'eth_rx_bytes', 'eth_tx_bytes', 'cpu_idle')
HEADER = struct.Struct('<4sHHIIQIII')
FIELDS = ['version', 'type', 'seq', 'scene', 'mtime', 'window_cyc', 'ds_busy', 'dir_switch']
FIELDS += [f'p{p}_{field}' for p in range(7) for field in PORT_FIELDS]
PERIOD_FIELDS = FIELDS + list(TAIL_FIELDS) + ['clk_sys_hz', 'clk_npu_hz', 'vid_skip']
HIST_FIELDS = ['hist_width', 'read_cnt', 'lat_min', 'lat_max', 'lat_sum']
HIST_FIELDS += [f'hist{i}' for i in range(16)]
FIELDS = PERIOD_FIELDS + HIST_FIELDS


def counter_delta(current, previous):
    """Software converts free-running u32 counters to window deltas before transmission."""
    return (current - previous) & 0xffffffff


def decode(data):
    if len(data) != RECORD_BYTES:
        raise ValueError(f'EDTM record length {len(data)}, expected 320')
    magic, version, kind, seq, scene, mtime, window, busy, switches = HEADER.unpack_from(data)
    if magic != b'EDTM':
        raise ValueError(f'EDTM magic mismatch: {magic!r}')
    if version != 1:
        raise ValueError(f'EDTM version {version}, expected 1')
    record = dict.fromkeys(FIELDS, 0)
    record.update(version=version, type=kind, seq=seq, scene=scene, mtime=mtime)
    if kind == 1:
        values = [version, kind, seq, scene, mtime, window, busy, switches]
        values += list(struct.unpack_from('<65I', data, 36))
        record.update(zip(PERIOD_FIELDS, values))
    elif kind == 2:
        record.update(zip(HIST_FIELDS, struct.unpack_from('<21I', data, 24)))
        record['clk_sys_hz'] = struct.unpack_from('<I', data, 108)[0]
    else:
        raise ValueError(f'EDTM record type {kind} is not defined')
    return record


def encode(record):
    data = bytearray(RECORD_BYTES)
    struct.pack_into('<4sHHIIQ', data, 0, b'EDTM',
                     *(record[name] for name in FIELDS[:5]))
    if record['type'] == 1:
        struct.pack_into('<68I', data, 24,
                         *(record[name] for name in PERIOD_FIELDS[5:]))
    else:
        struct.pack_into('<21I', data, 24, *(record[name] for name in HIST_FIELDS))
        struct.pack_into('<I', data, 108, record['clk_sys_hz'])
    return bytes(data)


def measurements(record):
    window = record['window_cyc']
    ports = []
    for p, name in enumerate(PORTS):
        raw = {key: record[f'p{p}_{key}'] for key in PORT_FIELDS}
        transactions = raw['rd_txn'] + raw['wr_txn']
        ports.append(dict(raw, name=name,
                          read_Bps=raw['rd_beat'] * 32 * 125e6 / window,
                          write_Bps=raw['wr_beat'] * 32 * 125e6 / window,
                          wait_avg=raw['wait_sum'] / transactions if transactions else 0))
    return dict(record, time_s=record['mtime'] / record['clk_sys_hz'], ports=ports,
                utilization=record['ds_busy'] / window,
                npu_ms=record['npu_cycles'] * 1000 / record['clk_npu_hz'],
                post_ms=record['post_cycles'] * 1000 / record['clk_sys_hz'],
                detection_fps=record['npu_completed'] * 125e6 / window)


class Telemetry:
    def __init__(self):
        self.lock = threading.RLock()
        self.clear()

    def clear(self):
        with self.lock:
            self.records = []
            self.history = deque()
            self.latest = None
            self.histogram = None
            self.last_seq = None
            self.lost = 0
            self.video_skipped = 0
            self.errors = 0
            self.error = None
            self.fragments = {}

    def ingest(self, data):
        with self.lock:
            try:
                record = decode(data)
            except ValueError as exc:
                self.errors += 1
                self.error = str(exc)
                raise
            seq = record['seq']
            if self.last_seq is not None:
                distance = counter_delta(seq, self.last_seq)
                if distance == 0 or distance >= 0x80000000:
                    return
                self.lost += distance - 1
            self.last_seq = seq
            self.records.append(record)
            if record['type'] == 2:
                self.histogram = record
                return
            self.video_skipped += record['vid_skip']
            self.latest = measurements(record)
            self.history.append(self.latest)
            while self.history and self.history[0]['time_s'] < self.latest['time_s'] - 60:
                self.history.popleft()

    def receive(self, offset, data, notify):
        """Reassemble record fragments using the ETH byte offset, never concatenate gaps."""
        with self.lock:
            if offset == 0:
                self.fragments.clear()
            position = 0
            while position < len(data):
                base = (offset + position) // RECORD_BYTES * RECORD_BYTES
                within = (offset + position) % RECORD_BYTES
                size = min(RECORD_BYTES - within, len(data) - position)
                raw, present = self.fragments.setdefault(
                    base, (bytearray(RECORD_BYTES), bytearray(RECORD_BYTES)))
                raw[within:within + size] = data[position:position + size]
                present[within:within + size] = b'\1' * size
                if all(present):
                    self.ingest(raw)
                    del self.fragments[base]
                position += size
            if notify:
                self.fragments.clear()

    def status(self):
        with self.lock:
            return dict(latest=self.latest, histogram=self.histogram, lost=self.lost,
                        errors=self.errors, error=self.error, records=len(self.records),
                        video_skipped=self.video_skipped)

    def snapshot(self):
        with self.lock:
            return list(self.history), self.status()

    def csv_text(self):
        with self.lock:
            stream = io.StringIO(newline='')
            writer = csv.DictWriter(stream, FIELDS)
            writer.writeheader()
            writer.writerows(self.records)
            return stream.getvalue()

    def export_csv(self, path):
        with Path(path).open('w', encoding='utf-8', newline='') as output:
            output.write(self.csv_text())
        return dict(path=str(path), records=len(self.records))

    def load_csv(self, path):
        with Path(path).open(encoding='utf-8', newline='') as stream:
            records = [{key: int(value) for key, value in row.items()}
                       for row in csv.DictReader(stream)]
        self.clear()
        for record in records:
            self.ingest(encode(record))
        return self.status()
