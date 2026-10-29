"""test_program.py — SoC 7.5(3a) BIOS prompts and fake UART; host, no clock domain."""

from pathlib import Path
import struct
import threading
import time
import unittest
from tempfile import TemporaryDirectory

from tools.board.uart_tool import wire_bytes
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
        if not self.selected:
            if data != b"1\r":
                raise AssertionError(f"BIOS expected menu selection 1 + CR, got {data!r}")
            self.selected = True
            self.inject(b"UART download ready\r\n")
        else:
            self.image.extend(data)
            if len(self.image) >= 4 and not self.result_sent:
                length = struct.unpack("<I", self.image[:4])[0]
                if length == 0:
                    self.result_sent = True
                    self.inject(b"Program SRAM result: FAIL length\r\n"
                                b"BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud\r\n")
                elif len(self.image) == length + 4:
                    self.result_sent = True
                    self.inject(f"Program SRAM bytes: {length}\r\n".encode()
                                + b"Program SRAM result: PASS, press reset to run\r\n"
                                + b"BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud\r\n")
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
        self.engine.start_program(path)
        return path

    def boot(self):
        self.serial.inject(b"Boot ROM startup\r\nBIOS: EdRV32\r\n"
                           b"BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud\r\n")

    def test_menu_ready_wire_and_result_keep_console_output(self):
        data = bytes(range(256)) * 41 + b"tail"
        path = self.start_image(data)
        self.assertEqual(self.serial.writes, [])
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"]
                 and self.engine.program.status()["sent"] == len(data) + 4)
        state = self.engine.program.status()
        self.assertTrue(state["bios"])
        self.assertEqual(self.serial.writes[0], b"1\r")
        self.assertEqual(b"".join(self.serial.writes[1:]), wire_bytes(path))
        self.assertEqual(state["sent"], len(data) + 4)
        self.assertEqual(state["total"], len(data) + 4)
        self.assertEqual(state["programmedBytes"], len(data))
        self.assertEqual(state["result"], "Program SRAM result: PASS, press reset to run")
        self.assertIsNone(state["error"])
        entries, _ = self.engine.get_entries()
        rx = [entry["text"] for entry in entries if entry["dir"] == "rx"]
        for text in ("BIOS: EdRV32", "BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud",
                     "UART download ready",
                     f"Program SRAM bytes: {len(data)}", state["result"]):
            self.assertIn(text, rx)
        self.assertEqual(self.engine.status()["txBytes"], len(data) + 6)

    def test_wait_for_menu_then_ready_exact_lines(self):
        self.start_image(b"x")
        self.engine.program.feed_line("UART download ready")
        self.engine.program.feed_line("BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud extra")
        self.assertEqual(self.serial.writes, [])
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"])
        self.assertEqual(b"".join(self.serial.writes), b"1\r\x01\0\0\0x")
        # The menu reprinted after completion must not start a second download.
        self.engine.program.feed_line("BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud")
        self.assertEqual(len(self.serial.writes), 2)

    def test_fail_length_result(self):
        path = self.start_image(b"")
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"])
        state = self.engine.program.status()
        self.assertEqual(b"".join(self.serial.writes[1:]), wire_bytes(path))
        self.assertEqual(state["result"], "Program SRAM result: FAIL length")
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
                reply += b'BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud\r\n'
            self.inject(reply)
        return len(data)


class ElfProgramTest(unittest.TestCase):
    def exercise(self, baud):
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
            engine.start_program(path, elf=True, baud=baud)
            peer.inject(b'BIOS: EdRV32\r\nBIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud\r\n')
            wait_for(self, lambda: not engine.program.status()['active'])
            actual = b''.join(peer.writes)
            expected = b''.join(data for data, _ in expected_steps(baud))
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

    def test_load_elf_and_run_at_921600(self):
        self.exercise(921600)

    def test_load_elf_and_run_without_baud_switch(self):
        self.exercise(115200)
