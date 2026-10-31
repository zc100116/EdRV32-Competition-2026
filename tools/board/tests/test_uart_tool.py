# File: test_uart_tool.py
# Spec: edrv32-soc-spec 7.5(3a), eth-spec 2.3.
# Description: Exercise real host session encoding, prompts and bounded ETH resend.
# Clock domain: none (host).
from pathlib import Path
import socket
import io
from types import SimpleNamespace
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch
from tools.board.uart_tool import (
    BIOS_MENU, BiosTransfer, capture, descriptor_bytes, elf_segments, eth_packets,
    operations, wire_bytes,
)
from tools.board.tests.elf_fixture import ENTRY, SEGMENTS, elf_fixture, expected_steps

ROOT = Path(__file__).resolve().parents[3]


class BiosToolTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'app.elf'
        self.path.write_bytes(elf_fixture())

    def test_elf_physical_segments_filesz_and_entry(self):
        self.assertEqual(elf_segments(self.path), (ENTRY, SEGMENTS))
        plan = operations(self.path, elf=True, baud=115200)
        self.assertEqual(len(plan), 1)
        self.assertEqual(plan[0].selection, b'1\r')
        self.assertEqual(plan[0].payload, expected_steps(115200)[1][0])
        self.assertEqual(plan[0].success, f'Run: 0x{ENTRY:08x}')

    def test_bin_addresses_required(self):
        for kwargs in ({}, {'addr': 0x10000000}, {'entry': 0x10000000}):
            with self.assertRaisesRegex(ValueError, '.bin requires --addr and --entry'):
                operations(self.path, **kwargs)
        self.path.write_bytes(b'\x0a\x0d\0binary')
        op = operations(self.path, baud=115200, addr=0x80001000, entry=0x80001004)[0]
        self.assertEqual(op.payload, struct.pack('<IIII', 1, 0x80001004, 0x80001000, 9)
                         + self.path.read_bytes())
        self.assertEqual(op.payload, wire_bytes(self.path, 0x80001000, 0x80001004))

    def test_uart_prompt_and_auto_run(self):
        for baud in (115200, 921600, 2000000):
            writes = []
            switches = []
            transfer = BiosTransfer(writes.append, switches.append)
            transfer.start(self.path, elf=True, baud=baud)
            self.assertEqual(writes, [b'\r'])
            transfer.feed_line('BIOS: EdRV32')
            for data, reply in expected_steps(baud):
                if data in (b'4\r', b'1\r'):
                    transfer.feed_line(BIOS_MENU + ' extra')
                    transfer.feed_line(BIOS_MENU)
                for line in reply.decode().splitlines():
                    transfer.feed_line(line)
            self.assertEqual(b''.join(writes), b'\r' + b''.join(
                data for data, _ in expected_steps(baud)))
            state = transfer.status()
            self.assertEqual(state['programmedBytes'], sum(len(data) for _, data in SEGMENTS))
            self.assertEqual(state['result'], f'Run: 0x{ENTRY:08x}')
            self.assertEqual(state['sent'], state['total'])
            self.assertFalse(state['active'])
            self.assertEqual(switches, [] if baud == 115200 else [baud])

    def test_range_failure_stops(self):
        transfer = BiosTransfer(Mock(), Mock())
        transfer.start(self.path, elf=True, baud=115200)
        transfer.feed_line(BIOS_MENU)
        transfer.feed_line('UART load ready')
        transfer.feed_line('Load result: FAIL range')
        self.assertFalse(transfer.status()['active'])
        self.assertEqual(transfer.status()['result'], 'Load result: FAIL range')

    def test_eth_offsets_packet_size_and_notify(self):
        packets = eth_packets(ENTRY, SEGMENTS)
        for packet in packets:
            self.assertLessEqual(len(packet), 1472)
        ddr = [p for p in packets if p[0] == 2]
        self.assertEqual(b''.join(p[8:] for p in ddr), SEGMENTS[0][1])
        for index, packet in enumerate(ddr):
            self.assertEqual(struct.unpack('!BBHI', packet[:8]), (2, 0, 0, 0x100 + 1464 * index))
        self.assertEqual(struct.unpack('!BBHI', packets[-2][:8]), (3, 0, 0, 0x1203))
        self.assertEqual(packets[-2][8:], SEGMENTS[1][1])
        self.assertEqual(packets[-1][:8], b'\x03\x01\0\0\0\0\0\0')
        self.assertEqual(packets[-1][8:], descriptor_bytes(ENTRY, SEGMENTS))

    def test_eth_bind_and_exactly_one_resend(self):
        udp = Mock()
        with patch('tools.board.uart_tool.socket.socket', return_value=udp) as factory:
            writes = []
            transfer = BiosTransfer(writes.append, Mock())
            transfer.start(self.path, elf=True, baud=115200, eth=True, local_ip='192.168.1.9')
            factory.assert_called_once_with(socket.AF_INET, socket.SOCK_DGRAM)
            udp.bind.assert_called_once_with(('192.168.1.9', 0))
            transfer.feed_line(BIOS_MENU)
            self.assertEqual(writes, [b'\r', b'2\r'])
            self.assertEqual(udp.sendto.call_count, 0)
            transfer.feed_line('ETH load ready 192.168.1.10:5000')
            first = list(udp.sendto.call_args_list)
            failure = 'ETH load result: FAIL bytes win2=1 expect=8451 win3=37 expect=37'
            transfer.feed_line(failure)
            self.assertEqual(udp.sendto.call_args_list, first + first)
            transfer.feed_line(failure)
            self.assertEqual(udp.sendto.call_args_list, first + first)
            self.assertFalse(transfer.status()['active'])
            self.assertEqual(transfer.status()['result'], failure)
            udp.close.assert_called_once()

    def test_rom_is_part_of_same_session(self):
        self.path.write_bytes(elf_fixture(rom_slot=True))
        rom = ROOT / 'sw/apps/nes/roms/nrom-template.nes'
        op = operations(self.path, True, 115200, rom)[0]
        self.assertEqual(op.payload, expected_steps(115200, rom.read_bytes())[1][0])
        with self.assertRaisesRegex(ValueError, '--rom requires --elf'):
            operations(self.path, rom=rom)

    def test_cli_emit(self):
        output = Path(self.temp.name) / 'wire'
        subprocess.run([sys.executable, str(ROOT / 'tools/board/uart_tool.py'), str(self.path),
                        '--elf', '--emit', str(output)], check=True)
        self.assertEqual(output.read_bytes(), b''.join(d for d, _ in expected_steps()))

    def test_capture_fragmented_uart_switches_baud_and_logs(self):
        test = self
        menu = (BIOS_MENU + '\r\n').encode()
        probe_reply = b'Input error: type 1-4 then Enter\r\n' + menu
        steps = [(b'\r', probe_reply)] + expected_steps()

        class Peer:
            def __init__(self):
                self.pending = bytearray()
                self.writes = bytearray()
                self.step = 0
                self.offset = 0
                self.switches = []

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            @property
            def in_waiting(self):
                return min(7, len(self.pending))

            @property
            def baudrate(self):
                return self.switches[-1][0] if self.switches else 115200

            @baudrate.setter
            def baudrate(self, value):
                self.switches.append((value, self.step))

            def read(self, size):
                if not self.pending:
                    raise KeyboardInterrupt
                data = bytes(self.pending[:size])
                del self.pending[:size]
                return data

            def write(self, data):
                expected, reply = steps[self.step]
                test.assertEqual(data, expected[self.offset:self.offset + len(data)])
                self.writes.extend(data)
                self.offset += len(data)
                if self.offset == len(expected):
                    self.step += 1
                    self.offset = 0
                    self.pending.extend(reply)
                    if self.step > 1 and self.step % 2 and self.step < len(steps):
                        self.pending.extend(menu)

            def flush(self):
                pass

        peer = Peer()
        console = io.BytesIO()
        log = Path(self.temp.name) / 'capture.log'
        with patch.dict(sys.modules, {'serial': SimpleNamespace(Serial=lambda *args: peer)}), \
                patch('sys.stdout', SimpleNamespace(buffer=console)):
            with self.assertRaises(KeyboardInterrupt):
                capture('fake', self.path, log, None, None, elf=True)
        self.assertEqual(peer.step, len(steps))
        self.assertEqual(peer.switches, [(2000000, 3)])
        self.assertEqual(peer.writes, b''.join(data for data, _ in steps))
        expected_log = probe_reply + b''.join(
            reply + (menu if index % 2 and index != len(steps) - 2 else b'')
            for index, (_, reply) in enumerate(steps[1:]))
        self.assertEqual(log.read_bytes(), expected_log)
        self.assertEqual(console.getvalue(), expected_log)

    def test_rom_missing_symbols_and_oversize_stop_before_transfer(self):
        rom = Path(self.temp.name) / 'game.nes'
        rom.write_bytes(b'game')
        with self.assertRaisesRegex(ValueError, 'missing ROM slot symbol'):
            operations(self.path, elf=True, rom=rom)
        self.path.write_bytes(elf_fixture(rom_slot=True))
        from tools.board.tests.elf_fixture import ROM_SLOT_SIZE
        rom.write_bytes(bytes(ROM_SLOT_SIZE + 1))
        writes = []
        transfer = BiosTransfer(writes.append, Mock())
        with self.assertRaisesRegex(ValueError, 'exceeds ROM slot size'):
            transfer.start(self.path, elf=True, rom=rom)
        self.assertEqual(writes, [])
