#!/usr/bin/env python3
"""telemetry_sim.py — B2 design 3.5 synthetic UDP sender; host clock domain.

Generate v1 records at 100 Hz in batches of 16, without any GUI imports.
Run beside main.py: python3 telemetry_sim.py --seconds 10 --port 6000
"""

import argparse
import math
import socket
import time
from core.ethernet import packets
from core.telemetry import FIELDS, encode


def periodic(seq, tick, hz):
    record = dict.fromkeys(FIELDS, 0)
    record.update(version=1, type=1, seq=seq, scene=1 if tick < hz * 5 else 2,
                  mtime=int((tick + 1) * 100e6 / hz), window_cyc=int(125e6 / hz),
                  clk_sys_hz=100_000_000, clk_npu_hz=150_000_000)
    record['ds_busy'] = int(record['window_cyc'] * (.46 + .12 * math.sin(tick / hz)))
    for p in range(7):
        scale = (1 + .18 * math.sin(tick / hz * 2 + p))
        record[f'p{p}_rd_beat'] = int((p + 1) * 700000 / hz * scale)
        record[f'p{p}_wr_beat'] = int((7 - p) * 500000 / hz * scale) if p else 0
        record[f'p{p}_rd_txn'] = record[f'p{p}_rd_beat'] // 8
        record[f'p{p}_wr_txn'] = record[f'p{p}_wr_beat'] // 8
        record[f'p{p}_wait_sum'] = (p + 3) * (record[f'p{p}_rd_txn'] +
                                                        record[f'p{p}_wr_txn'])
        record[f'p{p}_wait_max'] = (p + 1) * 15
        record[f'p{p}_urg_cnt'] = int(p == 0 and tick % 101 == 0)
    record.update(npu_completed=int(tick % 5 == 0), npu_cycles=6_450_000,
                  post_cycles=1_470_000, boxes=8 + tick % 5)
    return record


def histogram(seq, tick, hz):
    record = dict.fromkeys(FIELDS, 0)
    record.update(version=1, type=2, seq=seq, scene=1 if tick < hz * 5 else 2,
                  mtime=int((tick + 1) * 100e6 / hz), clk_sys_hz=100_000_000,
                  hist_width=16, read_cnt=1200, lat_min=17, lat_max=251, lat_sum=63000)
    for i in range(16):
        record[f'hist{i}'] = int(300 * math.exp(-((i - 3) / 2.5) ** 2))
    return record


def run(host, port, seconds, hz):
    seq = 0
    batch = bytearray()
    started = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for tick in range(int(seconds * hz)):
            batch.extend(encode(periodic(seq, tick, hz)))
            seq = (seq + 1) & 0xffffffff
            if (tick + 1) % hz == 0:
                batch.extend(encode(histogram(seq, tick, hz)))
                seq = (seq + 1) & 0xffffffff
            while len(batch) >= 16 * 320:
                for packet in packets(batch[:16 * 320], 3, 0):
                    sock.sendto(packet, (host, port))
                del batch[:16 * 320]
            if tick == int(seconds * hz) - 1 and batch:
                for packet in packets(batch, 3, 0):
                    sock.sendto(packet, (host, port))
                batch.clear()
            delay = started + (tick + 1) / hz - time.monotonic()
            if delay > 0:
                time.sleep(delay)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=6000)
    parser.add_argument('--seconds', type=float, default=60)
    parser.add_argument('--hz', type=int, choices=range(10, 1001), default=100, metavar='10..1000')
    args = parser.parse_args()
    run(args.host, args.port, args.seconds, args.hz)


if __name__ == '__main__':
    main()
