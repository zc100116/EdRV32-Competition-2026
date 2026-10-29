# File: test_uart_tool.py
# Spec: edrv32-soc-spec 7.5(3a); Task B1-10.
# Description: Check physical ELF segments and every byte of BIOS transfers and CLI emission.
# Clock domain: none (host test).
from pathlib import Path
import io
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tools.board.uart_tool import BIOS_MENU, BiosTransfer, capture, elf_segments, wire_bytes
from tools.board.tests.elf_fixture import ENTRY, SEGMENTS, elf_fixture, expected_steps

ROOT = Path(__file__).resolve().parents[3]


class UartToolTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'app.elf'
        self.path.write_bytes(elf_fixture())

    def assert_bytes(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for index, (got, want) in enumerate(zip(actual, expected)):
            self.assertEqual(got, want, f'byte {index}')

    def test_elf_segments_use_file_size_and_physical_address(self):
        entry, segments = elf_segments(self.path)
        self.assertEqual(entry, ENTRY)
        self.assertEqual(len(segments), 2)
        for (address, data), (want_address, want_data) in zip(segments, SEGMENTS):
            self.assertEqual(address, want_address)
            self.assert_bytes(data, want_data)

    def exercise_transfer(self, baud):
        writes = []
        switches = []
        transfer = BiosTransfer(writes.append, lambda value: switches.append((value, len(writes))))
        transfer.start(self.path, elf=True, baud=baud)
        transfer.feed_line('BIOS: EdRV32')
        steps = expected_steps(baud)
        for index, (expected, response) in enumerate(steps):
            if index % 2 == 0:
                transfer.feed_line(BIOS_MENU)
            start = sum(len(data) for data in writes)
            if index % 2:
                # The preceding response is the ready prompt.
                transfer.feed_line(steps[index - 1][1].decode().strip())
            actual = b''.join(writes)[start:]
            if index % 2 == 0:
                actual = writes[-1]
            self.assert_bytes(actual, expected)
            if index % 2:
                for line in response.decode().splitlines():
                    transfer.feed_line(line)
        state = transfer.status()
        self.assertFalse(state['active'])
        self.assertEqual(state['result'], f'Run: 0x{ENTRY:08x}')
        self.assertEqual(state['programmedBytes'], sum(len(data) for _, data in SEGMENTS))
        self.assertEqual(state['sent'], state['total'])
        self.assertEqual(switches, [] if baud == 115200 else [(baud, 2)])
        self.assert_bytes(b''.join(writes), b''.join(data for data, _ in steps))

    def test_default_fast_elf_transfer(self):
        self.exercise_transfer(2000000)

    def test_921600_elf_transfer(self):
        self.exercise_transfer(921600)

    def test_115200_skips_baud_switch(self):
        self.exercise_transfer(115200)

    def test_fail_results_stop_transfer(self):
        for ready, response in [('Baud:', 'Baud result: FAIL'),
                                ('UART load ready', 'Load result: FAIL range'),
                                ('Run address:', 'Run result: FAIL address')]:
            writes = []
            transfer = BiosTransfer(writes.append, lambda value: None)
            transfer.start(self.path, elf=True)
            for expected, reply in expected_steps():
                if expected in (b'4\r', b'2\r', b'3\r'):
                    transfer.feed_line(BIOS_MENU)
                    transfer.feed_line(reply.decode().strip())
                    if reply.decode().strip() == ready:
                        transfer.feed_line(response)
                        break
                else:
                    for line in reply.decode().splitlines():
                        transfer.feed_line(line)
            self.assertFalse(transfer.status()['active'])
            self.assertEqual(transfer.status()['result'], response)
            before = list(writes)
            transfer.feed_line(BIOS_MENU)
            self.assertEqual(writes, before)

    def test_cli_emit_elf_and_unchanged_sram_stream(self):
        output = Path(self.temp.name) / 'wire'
        subprocess.run([sys.executable, str(ROOT / 'tools/board/uart_tool.py'), str(self.path),
                        '--elf', '--emit', str(output)], check=True)
        self.assert_bytes(output.read_bytes(), b''.join(data for data, _ in expected_steps()))
        data = bytes(range(256)) + b'\n\r\x00'
        self.path.write_bytes(data)
        subprocess.run([sys.executable, str(ROOT / 'tools/board/uart_tool.py'), str(self.path),
                        '--emit', str(output)], check=True)
        self.assert_bytes(output.read_bytes(), struct.pack('<I', len(data)) + data)
        self.assert_bytes(wire_bytes(self.path), output.read_bytes())

    def test_capture_fragmented_uart_switches_baud_and_logs(self):
        test = self
        steps = expected_steps()
        menu = (BIOS_MENU + '\r\n').encode()

        class Peer:
            def __init__(self):
                self.pending = bytearray(b'BIOS: EdRV32\r\n' + menu)
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
                test.assert_bytes(data, expected[self.offset:self.offset + len(data)])
                self.writes.extend(data)
                self.offset += len(data)
                if self.offset == len(expected):
                    self.step += 1
                    self.offset = 0
                    self.pending.extend(reply)
                    if self.step % 2 == 0 and self.step < len(steps):
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
        self.assertEqual(peer.switches, [(2000000, 2)])
        self.assert_bytes(peer.writes, b''.join(data for data, _ in steps))
        expected_log = b'BIOS: EdRV32\r\n' + menu + b''.join(
            reply + (menu if index % 2 and index != len(steps) - 1 else b'')
            for index, (_, reply) in enumerate(steps))
        self.assert_bytes(log.read_bytes(), expected_log)
        self.assert_bytes(console.getvalue(), expected_log)
