"""test_program.py — SoC 7.5(3a) BIOS prompts and fake UART; host, no clock domain."""

from pathlib import Path
import struct
import threading
import time
import unittest
from tempfile import TemporaryDirectory

from tools.board.uart_tool import BIOS_MENU, wire_bytes
from tools.debug_tool.core.engine import SerialEngine


def wait_for(test, condition):
    deadline = time.monotonic() + 3
    while not condition() and time.monotonic() < deadline:
        time.sleep(0.005)
    test.assertTrue(condition(), "timed out waiting for fake UART / UDP operation")


class FakeSerial:
    """An in-memory BIOS peer; engine reads fragmented CR LF lines normally."""
    def __init__(self):
        self.is_open = True
        self.port = "memory BIOS"
        self.condition = threading.Condition()
        self.pending = bytearray()
        self.writes = []
        self.image = bytearray()
        self.selected = False
        self.result_sent = False
        self.in_bios = False

    @property
    def in_waiting(self):
        with self.condition:
            return min(7, len(self.pending))

    def inject(self, data):
        with self.condition:
            self.pending.extend(data)
            self.condition.notify_all()

    def read(self, size):
        with self.condition:
            if not self.pending:
                self.condition.wait(0.01)
            data = bytes(self.pending[:size])
            del self.pending[:size]
            return data

    def write(self, data):
        self.writes.append(bytes(data))
        if data == b"\r" and not self.selected:
            if self.in_bios:
                self.inject(b"Input error: type 1-4 then Enter\r\n"
                            + (BIOS_MENU + "\r\n").encode())
            else:
                self.inject(b"Input error\r\n")
            return len(data)
        if not self.selected:
            if data != b"1\r":
                raise AssertionError(f"BIOS expected menu selection 1 + CR, got {data!r}")
            self.selected = True
            self.image.clear()
            self.result_sent = False
            self.inject(b"UART load ready\r\n")
        else:
            self.image.extend(data)
            if len(self.image) >= 16 and not self.result_sent:
                length = struct.unpack("<I", self.image[12:16])[0]
                if length == 0:
                    self.result_sent = True
                    self.selected = False
                    self.inject(b"Load result: FAIL range\r\n"
                                b"BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud\r\n")
                elif len(self.image) == length + 16:
                    self.result_sent = True
                    self.selected = False
                    self.inject(f"Load bytes: {length} segments: 1\r\n".encode()
                                + b"Load result: PASS\r\nRun: 0x10000000\r\n"
                                + b"BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud\r\n")
        return len(data)

    def close(self):
        self.is_open = False


class ProgramTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.engine = SerialEngine()
        self.serial = FakeSerial()
        self.engine._serial = self.serial
        self.engine._reader_running = True
        self.engine._reader = threading.Thread(target=self.engine._reader_loop)
        self.engine._reader.start()
        self.addCleanup(self.engine.disconnect, silent=True)

    def start_image(self, data):
        path = Path(self.temp.name) / "app.bin"
        path.write_bytes(data)
        self.engine.start_program(path, baud=115200, addr=0x10000000, entry=0x10000000)
        return path

    def boot(self):
        self.serial.in_bios = True
        self.serial.inject(b"Boot ROM startup\r\nBIOS: EdRV32\r\n"
                           b"BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud\r\n")

    def test_menu_ready_wire_and_result_keep_console_output(self):
        data = bytes(range(256)) * 41 + b"tail"
        path = self.start_image(data)
        self.assertEqual(self.serial.writes, [b"\r"])
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"]
                 and self.engine.program.status()["sent"] == len(data) + 16)
        state = self.engine.program.status()
        self.assertTrue(state["bios"])
        self.assertEqual(self.serial.writes[:2], [b"\r", b"1\r"])
        self.assertEqual(b"".join(self.serial.writes[2:]), wire_bytes(path, 0x10000000, 0x10000000))
        self.assertEqual(state["sent"], len(data) + 16)
        self.assertEqual(state["total"], len(data) + 16)
        self.assertEqual(state["programmedBytes"], len(data))
        self.assertEqual(state["result"], "Run: 0x10000000")
        self.assertIsNone(state["error"])
        entries, _ = self.engine.get_entries()
        rx = [entry["text"] for entry in entries if entry["dir"] == "rx"]
        for text in ("BIOS: EdRV32", "BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud",
                     "UART load ready",
                     f"Load bytes: {len(data)} segments: 1", state["result"]):
            self.assertIn(text, rx)
        self.assertEqual(self.engine.status()["txBytes"], len(data) + 19)

    def wait_for_menu_output(self, count=1):
        wait_for(self, lambda: sum(
            entry["dir"] == "rx" and entry["text"] == BIOS_MENU
            for entry in self.engine.get_entries()[0]) >= count)

    def test_enter_bios_before_start_program(self):
        self.boot()
        self.wait_for_menu_output()
        self.assertEqual(self.serial.writes, [])
        path = self.start_image(b"already in BIOS")
        wait_for(self, lambda: not self.engine.program.status()["active"])
        self.assertEqual(b"".join(self.serial.writes),
                         b"\r1\r" + wire_bytes(path, 0x10000000, 0x10000000))
        self.assertEqual(self.engine.program.status()["result"],
                         "Run: 0x10000000")
        self.assertFalse(self.engine.program.status()["bios"])
        self.assertIn("已在 BIOS 菜单时直接开始；否则按住 KEY1 并复位",
                      [entry["text"] for entry in self.engine.get_entries()[0]
                       if entry["dir"] == "sys"])

    def test_two_programs_in_one_bios_session(self):
        self.boot()
        self.wait_for_menu_output()
        expected = b""
        for index, payload in enumerate((b"first image", b"second image"), 1):
            path = self.start_image(payload)
            wait_for(self, lambda: not self.engine.program.status()["active"])
            self.wait_for_menu_output(1 + 2 * index)
            expected += b"\r1\r" + wire_bytes(path, 0x10000000, 0x10000000)
            self.assertEqual(b"".join(self.serial.writes), expected)
            self.assertEqual(self.engine.program.status()["programmedBytes"], len(payload))
            self.assertEqual(self.engine.program.status()["result"],
                             "Run: 0x10000000")

    def test_wait_for_menu_then_ready_exact_lines(self):
        self.engine.program.feed_line(BIOS_MENU)
        self.start_image(b"x")
        self.engine.program.feed_line("UART load ready")
        self.engine.program.feed_line("BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud extra")
        self.assertEqual(self.serial.writes, [b"\r"])
        self.assertEqual(self.engine.program.status()["phase"], "wait_menu")
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"])
        self.assertEqual(b"".join(self.serial.writes), b"\r1\r" +
                         struct.pack("<IIII", 1, 0x10000000, 0x10000000, 1) + b"x")
        # The menu reprinted after completion must not start a second download.
        self.engine.program.feed_line("BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud")
        self.assertEqual(len(self.serial.writes), 3)

    def test_fail_length_result(self):
        path = self.start_image(b"")
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"])
        state = self.engine.program.status()
        self.assertEqual(b"".join(self.serial.writes[2:]), wire_bytes(path, 0x10000000, 0x10000000))
        self.assertEqual(state["result"], "Load result: FAIL range")
        self.assertIsNone(state["programmedBytes"])

    def test_disconnect_reports_error(self):
        self.start_image(b"x")
        self.engine.disconnect(silent=True)
        state = self.engine.program.status()
        self.assertFalse(state["active"])
        self.assertEqual(state["phase"], "error")
        self.assertIn("disconnected", state["error"])


class ElfSerial(FakeSerial):
    """Independent scripted ELF peer, including fragmented input and baud changes."""
    def __init__(self, baud):
        super().__init__()
        from tools.board.tests.elf_fixture import expected_steps
        self.steps = expected_steps(baud)
        self.step = 0
        self.step_bytes = bytearray()
        self.switches = []
        self._baudrate = 115200

    @property
    def baudrate(self):
        return self._baudrate

    @baudrate.setter
    def baudrate(self, value):
        self._baudrate = value
        self.switches.append((value, self.step))

    def write(self, data):
        if self.step == 0 and data == b'\r':
            return super().write(data)
        self.writes.append(bytes(data))
        expected, reply = self.steps[self.step]
        offset = len(self.step_bytes)
        for index, byte in enumerate(data):
            if byte != expected[offset + index]:
                raise AssertionError(f'ELF step={self.step} byte={offset + index}: {byte}')
        self.step_bytes.extend(data)
        if len(self.step_bytes) == len(expected):
            self.step += 1
            self.step_bytes.clear()
            if self.step % 2 == 0 and self.step < len(self.steps):
                reply += b'BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud\r\n'
            self.inject(reply)
        return len(data)


class ElfProgramTest(unittest.TestCase):
    def exercise(self, baud, bios_first=False):
        from tools.board.tests.elf_fixture import ENTRY, SEGMENTS, elf_fixture, expected_steps
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'app.elf'
            path.write_bytes(elf_fixture())
            engine = SerialEngine()
            self.addCleanup(engine.disconnect, silent=True)
            peer = ElfSerial(baud)
            engine._serial = peer
            engine._reader_running = True
            engine._reader = threading.Thread(target=engine._reader_loop)
            engine._reader.start()
            if bios_first:
                peer.in_bios = True
                peer.inject((BIOS_MENU + '\r\n').encode())
                wait_for(self, lambda: any(
                    entry['dir'] == 'rx' and entry['text'] == BIOS_MENU
                    for entry in engine.get_entries()[0]))
                self.assertEqual(peer.writes, [])
            engine.start_program(path, elf=True, baud=baud)
            if not bios_first:
                self.assertEqual(peer.writes, [b'\r'])
                self.assertEqual(engine.program.status()['phase'], 'wait_menu')
                peer.in_bios = True
                peer.inject(b'BIOS: EdRV32\r\n' + (BIOS_MENU + '\r\n').encode())
            wait_for(self, lambda: not engine.program.status()['active'])
            actual = b''.join(peer.writes)
            expected = b'\r' + b''.join(data for data, _ in expected_steps(baud))
            self.assertEqual(len(actual), len(expected))
            for index, (got, want) in enumerate(zip(actual, expected)):
                self.assertEqual(got, want, f'byte {index}')
            self.assertEqual(peer.switches, [] if baud == 115200 else [(baud, 2)])
            state = engine.program.status()
            self.assertEqual(state['programmedBytes'], sum(len(data) for _, data in SEGMENTS))
            self.assertEqual(state['result'], f'Run: 0x{ENTRY:08x}')
            self.assertIsNone(state['error'])
            self.assertEqual(state['sent'], state['total'])
            if baud != 115200:
                self.assertEqual(engine.status()['config']['baud'], baud)

    def test_load_elf_and_run_at_2000000(self):
        self.exercise(2000000)

    def test_enter_bios_before_load_ddr_elf(self):
        self.exercise(2000000, bios_first=True)

    def test_load_elf_and_run_at_921600(self):
        self.exercise(921600)

    def test_load_elf_and_run_without_baud_switch(self):
        self.exercise(115200)


class EthProgramTest(unittest.TestCase):
    def test_transport_addresses_and_retry_use_shared_bios(self):
        from unittest.mock import Mock, patch
        from tools.debug_tool.core.program import BiosProgrammer
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'app.bin'
            path.write_bytes(b'ethernet image')
            udp = Mock()
            writes = []
            programmer = BiosProgrammer(writes.append, Mock(), Mock())
            with patch('tools.board.uart_tool.socket.socket', return_value=udp):
                programmer.start(path, baud=115200, addr=0x80000100, entry=0x80000104,
                                 eth=True, local_ip='192.168.1.8')
            udp.bind.assert_called_once_with(('192.168.1.8', 0))
            programmer.feed_line(BIOS_MENU)
            programmer.feed_line('ETH load ready 192.168.1.10:5000')
            self.assertEqual(writes, [b'\r', b'2\r'])
            calls = list(udp.sendto.call_args_list)
            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[-1].args[0][8:],
                             struct.pack('<IIII', 1, 0x80000104, 0x80000100, 14))
            programmer.feed_line('ETH load result: FAIL bytes win2=0 expect=14 win3=16 expect=16')
            self.assertEqual(udp.sendto.call_args_list, calls + calls)
            programmer.feed_line('Load bytes: 14 segments: 1')
            programmer.feed_line('Load result: PASS')
            programmer.feed_line('Run: 0x80000104')
            self.assertFalse(programmer.status()['active'])
            self.assertEqual(programmer.status()['programmedBytes'], 14)
            udp.close.assert_called_once()
