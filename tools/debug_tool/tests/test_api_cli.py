"""test_api_cli.py — BIOS scripting and UDP HTTP integration; host, no clock domain."""

from pathlib import Path
import json
import subprocess
import sys
import threading
import unittest
import urllib.request
from tempfile import TemporaryDirectory

from tools.board.uart_tool import wire_bytes
from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.engine import SerialEngine
from test_program import FakeSerial, wait_for

TOOL_DIR = Path(__file__).resolve().parents[1]


class ApiCliTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.engine = SerialEngine()
        self.addCleanup(self.engine.ethernet.stop_receive)
        self.serial = FakeSerial()
        self.engine._serial = self.serial
        self.engine._reader_running = True
        self.engine._reader = threading.Thread(target=self.engine._reader_loop)
        self.engine._reader.start()
        self.addCleanup(self.engine.disconnect, silent=True)
        self.api = ApiServer(self.engine, port=0)
        self.api.start()
        self.addCleanup(self.api.stop)
        self.url = f"http://127.0.0.1:{self.api._httpd.server_port}"

    def request(self, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.url + path, data=data,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=3) as response:
            return json.load(response)

    def boot(self):
        self.serial.inject(b"BIOS: EdRV32\r\nBIOS menu: 1=Program SRAM\r\n")

    def test_rest_program_and_console(self):
        path = Path(self.temp.name) / "app.bin"
        path.write_bytes(b"REST BIOS payload")
        state = self.request("/api/program", {"path": str(path)})
        self.assertEqual(state["phase"], "wait_menu")
        self.boot()
        wait_for(self, lambda: not self.engine.program.status()["active"])
        state = self.request("/api/program/status")
        self.assertEqual(state["programmedBytes"], path.stat().st_size)
        self.assertEqual(state["result"], "Program SRAM result: PASS, press reset to run")
        self.assertEqual(b"".join(self.serial.writes[1:]), wire_bytes(path))
        entries = self.request("/api/buffer")["entries"]
        self.assertIn(state["result"], [e["text"] for e in entries if e["dir"] == "rx"])

    def run_cli(self, payload):
        path = Path(self.temp.name) / "cli.bin"
        path.write_bytes(payload)
        process = subprocess.Popen(
            [sys.executable, str(TOOL_DIR / "cli.py"), "--url", self.url, "program", str(path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        wait_for(self, lambda: self.engine.program.status()["active"])
        self.boot()
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(stderr, "")
        self.assertEqual(b"".join(self.serial.writes[1:]), wire_bytes(path))
        return process.returncode, stdout

    def test_cli_program_success(self):
        code, stdout = self.run_cli(b"CLI BIOS payload")
        self.assertEqual(code, 0)
        self.assertIn("按住 KEY1 按复位", stdout)
        self.assertIn("Program SRAM result: PASS, press reset to run", stdout)
        self.assertIn('"programmedBytes": 16', stdout)

    def test_cli_program_failure_exit_status(self):
        code, stdout = self.run_cli(b"")
        self.assertEqual(code, 1)
        self.assertIn("Program SRAM result: FAIL length", stdout)

    def test_rest_udp_file_loopback(self):
        path = Path(self.temp.name) / "udp.bin"
        data = bytes(range(256)) * 9
        path.write_bytes(data)
        rx = self.request("/api/ethernet/receive/start", {
            "localPort": 0, "directory": str(Path(self.temp.name) / "received")})
        # The running listener is also the source socket, just as in the GUI.
        self.request("/api/ethernet/send", {
            "path": str(path), "boardIp": "127.0.0.1", "boardPort": rx["localPort"],
            "localPort": rx["localPort"], "window": 2, "offset": 0, "interval": 0.001})
        wait_for(self, lambda: self.engine.ethernet.status()["rx"]["packets"] == 3)
        wait_for(self, lambda: not self.engine.ethernet.status()["tx"]["active"])
        state = self.request("/api/ethernet/status")
        self.assertEqual(state["tx"]["sent"], len(data))
        self.assertIsNone(state["tx"]["error"])
        rx = self.request("/api/ethernet/receive/stop", {})
        self.assertEqual(rx["bytes"], len(data))
        self.assertEqual(rx["notifyCount"], 1)
        self.assertEqual(Path(rx["files"]["2"]).read_bytes(), data)
