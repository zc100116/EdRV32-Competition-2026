"""test_telemetry.py — B2 design 3.5 wire vectors and UDP; host clock domain."""

import csv
import io
from pathlib import Path
import socket
import struct
from tempfile import TemporaryDirectory
import unittest

from tools.debug_tool.core.ethernet import EthernetTool, packets
from tools.debug_tool.core.telemetry import (
    Telemetry, counter_delta, decode, encode, measurements,
)
from test_program import wait_for


def wire(seq=0, kind=1):
    data = bytearray(320)
    struct.pack_into('<4sHHIIQ', data, 0, b'EDTM', 1, kind, seq, 2, 123456789)
    if kind == 1:
        struct.pack_into('<3I', data, 24, 1_250_000, 625_000, 34)
        for port in range(7):
            struct.pack_into('<7I', data, 36 + port * 28,
                             2, 31250 * (port + 1), 3, 15625, 45, 72, port)
        struct.pack_into('<13I', data, 232, 11, 12, 13, 14, 15, 16,
                         1, 6_000_000, 1_000_000, 7, 99, 100, 101)
        struct.pack_into('<3I', data, 284, 100_000_000, 150_000_000, 17)
    else:
        struct.pack_into('<5I', data, 24, 16, 100, 12, 300, 2600)
        struct.pack_into('<16I', data, 44, *range(16))
        struct.pack_into('<I', data, 108, 100_000_000)
    return bytes(data)


class TelemetryTest(unittest.TestCase):
    def test_manual_offsets_periodic(self):
        row = decode(wire())
        self.assertEqual(row['p6_rd_beat'], 218750)
        self.assertEqual(row['vin_ch0_frames'], 11)
        self.assertEqual(row['vin_ch2_overflow'], 14)
        self.assertEqual(row['disp_underflow'], 15)
        self.assertEqual(row['npu_completed'], 1)
        self.assertEqual(row['cpu_idle'], 101)
        self.assertEqual(row['clk_npu_hz'], 150_000_000)
        self.assertEqual(row['vid_skip'], 17)
        self.assertEqual(encode(row), wire())

    def test_manual_histogram_offsets(self):
        row = decode(wire(9, 2))
        self.assertEqual(row['hist_width'], 16)
        self.assertEqual(row['lat_sum'], 2600)
        self.assertEqual(row['hist15'], 15)
        self.assertEqual(encode(row), wire(9, 2))
        telemetry = Telemetry()
        telemetry.ingest(wire(8))
        telemetry.ingest(wire(9, 2))
        self.assertEqual(telemetry.status()['histogram']['hist15'], 15)
        self.assertEqual(telemetry.status()['latest']['seq'], 8)
        self.assertEqual(telemetry.status()['lost'], 0)

    def test_bandwidth_utilization_wait_and_clocks(self):
        value = measurements(decode(wire()))
        self.assertEqual(value['ports'][0]['read_Bps'], 100_000_000)
        self.assertEqual(value['ports'][0]['write_Bps'], 50_000_000)
        self.assertEqual(value['ports'][0]['wait_avg'], 9)
        self.assertEqual(value['ports'][0]['wait_max'], 72)
        self.assertEqual(value['utilization'], .5)
        self.assertEqual(value['npu_ms'], 40)
        self.assertEqual(value['post_ms'], 10)
        self.assertEqual(value['detection_fps'], 100)
        self.assertAlmostEqual(value['time_s'], 1.23456789)

    def test_zero_beats_and_no_transactions(self):
        data = bytearray(wire())
        struct.pack_into('<7I', data, 36, *([0] * 7))
        port = measurements(decode(data))['ports'][0]
        self.assertEqual(port['read_Bps'], 0)
        self.assertEqual(port['write_Bps'], 0)
        self.assertEqual(port['wait_avg'], 0)

    def test_counter_wrap_delta_and_sequence_loss(self):
        self.assertEqual(counter_delta(3, 0xfffffffe), 5)
        telemetry = Telemetry()
        for seq in (0xfffffffe, 0xffffffff, 0, 3):
            telemetry.ingest(wire(seq))
        self.assertEqual(telemetry.status()['lost'], 2)
        self.assertEqual(telemetry.status()['latest']['seq'], 3)

    def test_protocol_errors_are_counted_and_raised(self):
        telemetry = Telemetry()
        for change in ('magic', 'version', 'length'):
            data = bytearray(wire())
            if change == 'magic':
                data[:4] = b'BAD!'
            elif change == 'version':
                struct.pack_into('<H', data, 4, 2)
            else:
                data.pop()
            with self.assertRaises(ValueError):
                telemetry.ingest(data)
        self.assertEqual(telemetry.status()['errors'], 3)
        self.assertIn('length', telemetry.status()['error'])

    def test_csv_roundtrip_both_types(self):
        telemetry = Telemetry()
        telemetry.ingest(wire(5))
        telemetry.ingest(wire(7, 2))
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'samples.csv'
            telemetry.export_csv(path)
            replay = Telemetry()
            replay.load_csv(path)
        self.assertEqual(telemetry.records, replay.records)
        self.assertEqual(replay.status()['lost'], 1)
        self.assertEqual(len(list(csv.DictReader(io.StringIO(replay.csv_text())))), 2)

    def test_history_is_60_seconds(self):
        telemetry = Telemetry()
        for i in range(80):
            data = bytearray(wire(i))
            struct.pack_into('<Q', data, 16, i * 100_000_000)
            telemetry.ingest(data)
        self.assertEqual(len(telemetry.history), 61)
        self.assertEqual(len(telemetry.records), 80)

    def test_udp_batch_fragmentation_and_dropped_datagram(self):
        telemetry = Telemetry()
        receiver = EthernetTool(telemetry)
        self.addCleanup(receiver.stop_receive)
        with TemporaryDirectory() as directory:
            rx = receiver.start_receive(0, directory)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                batch = b''.join(wire(i) for i in range(16))
                for packet in packets(batch, 3, 0):
                    sock.sendto(packet, ('127.0.0.1', rx['localPort']))
                wait_for(self, lambda: telemetry.status()['records'] == 16)
                chunks = list(packets(b''.join(wire(i) for i in range(16, 32)), 3, 0))
                for i, packet in enumerate(chunks):
                    if i != 1:
                        sock.sendto(packet, ('127.0.0.1', rx['localPort']))
                wait_for(self, lambda: telemetry.status()['latest']['seq'] == 31)
            receiver.stop_receive()
            self.assertEqual(telemetry.status()['lost'], 4)
            self.assertIsNone(receiver.status()['rx']['error'])

    def test_udp_bad_magic_stops_and_reports_error(self):
        telemetry = Telemetry()
        receiver = EthernetTool(telemetry)
        self.addCleanup(receiver.stop_receive)
        with TemporaryDirectory() as directory:
            rx = receiver.start_receive(0, directory)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                bad = b'BAD!' + wire()[4:]
                sock.sendto(next(packets(bad, 3, 0)), ('127.0.0.1', rx['localPort']))
            wait_for(self, lambda: not receiver.status()['rx']['active'])
            self.assertEqual(telemetry.status()['errors'], 1)
            self.assertIn('magic', receiver.status()['rx']['error'])
