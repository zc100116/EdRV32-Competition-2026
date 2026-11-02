"""test_telemetry_api.py — B2 design 3.6 shared REST/CLI/headless; host clock domain."""

import json
from pathlib import Path
import socket
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
import urllib.request

from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.ethernet import packets
from test_program import wait_for
from test_telemetry import wire
from test_yolo import compiler_fixture

TOOL = Path(__file__).resolve().parents[1]


class TelemetryApiTest(unittest.TestCase):
    def setUp(self):
        ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                      return_value=('loopback', 0.0))
        ready.start()
        self.addCleanup(ready.stop)
        self.engine = SerialEngine()
        self.engine.ethernet.local_ip = "127.0.0.1"
        self.addCleanup(self.engine.ethernet.stop_receive)
        self.api = ApiServer(self.engine, port=0)
        self.api.start()
        self.addCleanup(self.api.stop)
        self.url = f'http://127.0.0.1:{self.api._httpd.server_port}'

    def request(self, path, body=None):
        request = urllib.request.Request(self.url + path,
                                         data=None if body is None else json.dumps(body).encode(),
                                         headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=3) as response:
            return json.load(response)

    def test_rest_latest_export_replay_and_csv_download(self):
        self.engine.telemetry.ingest(wire(7))
        self.assertEqual(self.request('/api/telemetry')['latest']['seq'], 7)
        with TemporaryDirectory() as directory:
            path = str(Path(directory) / 'monitor.csv')
            self.assertEqual(self.request('/api/telemetry/export', {'path': path})['records'], 1)
            self.request('/api/telemetry/clear', {})
            self.assertIsNone(self.request('/api/telemetry')['latest'])
            self.request('/api/telemetry/replay', {'path': path})
            with urllib.request.urlopen(self.url + '/api/telemetry/csv') as response:
                self.assertEqual(response.read().decode(), Path(path).read_bytes().decode())

    def test_cli_observes_same_latest_and_exports(self):
        self.engine.telemetry.ingest(wire(8))
        with TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(TOOL / 'cli.py'), '--url', self.url,
                                     'telemetry', 'latest'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['latest']['seq'], 8)
            path = str(Path(directory) / 'cli.csv')
            result = subprocess.run([sys.executable, str(TOOL / 'cli.py'), '--url', self.url,
                                     'telemetry', 'export', path], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('clk_npu_hz', Path(path).read_text())

    def test_rest_model_and_return_windows_offsets(self):
        with TemporaryDirectory() as directory:
            compiler_fixture(directory)
            rx = self.request('/api/ethernet/receive/start',
                              {'localIp': '127.0.0.1', 'localPort': 0,
                               'directory': str(Path(directory) / 'rx')})
            self.request('/api/yolo/model', {'path': directory, 'boardIp': '127.0.0.1',
                                             'boardPort': rx['localPort'], 'localPort': 0})
            wait_for(self, lambda: self.engine.ethernet.status()['rx']['packets'] == 4)
            wait_for(self, lambda: not self.engine.ethernet.status()['tx']['active'])
            self.assertEqual(self.request('/api/ethernet/status')['tx']['sent'], 1376)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                for window in range(3):
                    data = bytes([window + 1]) * (window + 4)
                    for packet in packets(data, window, 17):
                        sock.sendto(packet, ('127.0.0.1', rx['localPort']))
            wait_for(self, lambda: self.engine.ethernet.status()['rx']['packets'] == 7)
            state = self.request('/api/ethernet/receive/stop', {})
            for window in range(3):
                contents = Path(state['files'][str(window)]).read_bytes()
                self.assertEqual(contents[17:17 + window + 4], bytes([window + 1]) * (window + 4))

    def test_actual_headless_process_udp_to_rest(self):
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        process = subprocess.Popen([sys.executable, str(TOOL / 'main.py'), '--headless',
                                    '--api-port', str(port)], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        self.url = f'http://127.0.0.1:{port}'
        def ready():
            try:
                return self.request('/api/telemetry')['records'] == 0
            except urllib.error.URLError:
                return False
        wait_for(self, ready)
        with TemporaryDirectory() as directory:
            rx = self.request('/api/ethernet/receive/start',
                              {'localIp': '127.0.0.1', 'localPort': 0, 'directory': directory})
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.sendto(next(packets(wire(42), 3, 0)), ('127.0.0.1', rx['localPort']))
            wait_for(self, lambda: self.request('/api/telemetry')['records'] == 1)
            self.assertEqual(self.request('/api/telemetry')['latest']['seq'], 42)
            self.request('/api/ethernet/receive/stop', {})
        process.terminate()
