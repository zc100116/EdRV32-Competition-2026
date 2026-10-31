"""Task T-UI1: actual REST/CLI/serial transport, debounce and independent scale."""
import json
import os
from pathlib import Path
import pty
import subprocess
import sys
import threading
import time
import unittest
import urllib.request
from unittest.mock import patch

from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.engine import SerialEngine

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/debug_tool'))
from telemetry_sim import run_processing


class ProcessingTest(unittest.TestCase):
    def test_rest_cli_through_serial_simulator(self):
        engine = SerialEngine()
        master, slave = pty.openpty()
        self.addCleanup(os.close, slave)
        stream = os.fdopen(master, 'r+b', buffering=0)
        self.addCleanup(stream.close)
        # PTYs transport UART bytes but do not implement modem-control ioctls.
        with (patch('serial.serialposix.Serial._update_dtr_state'),
              patch('serial.serialposix.Serial._update_rts_state')):
            engine.connect(os.ttyname(slave), 115200)
        self.addCleanup(engine.disconnect, silent=True)
        api = ApiServer(engine, port=0)
        api.start()
        self.addCleanup(api.stop)
        url = f'http://127.0.0.1:{api._httpd.server_port}'
        received = []
        errors = []
        def board():
            try:
                received.extend(run_processing(stream, 2))
            except Exception as exc:
                errors.append(exc)
        worker = threading.Thread(target=board, daemon=True)
        worker.start()
        body = dict(bc=1, contrast=333, brightness=-77, gamma_en=1, gamma=2200,
                    stage1=6, stage2=4, gray=1, binary=1, threshold=149, invert=1)
        request = urllib.request.Request(url + '/api/processing/pix',
            data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=3) as response:
            self.assertEqual(response.status, 200)
        result = subprocess.run([sys.executable, str(ROOT / 'tools/debug_tool/cli.py'),
            '--url', url, 'processing', 'geo', json.dumps(dict(enabled=1, angle=123,
                scale_x=1400, scale_y=750, translate_x=-12, mirror_y=1))],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        worker.join(3)
        self.assertFalse(worker.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(received, ['pix set 1 333 -77 1 2200 6 4 1 1 149 1',
                                    'geo set 1 123 1400 750 -12 0 0 1'])
        deadline = time.monotonic() + 3
        while 'GEO parameters' not in engine.board.status()['summary']:
            self.assertLess(time.monotonic(), deadline)
            time.sleep(.01)
        self.assertIn('PIX parameters', engine.board.status()['summary'])
        with urllib.request.urlopen(url + '/api/processing') as response:
            self.assertEqual(json.load(response)['geo']['scale_y'], 750)

    def test_debounce_lock_and_all_operations(self):
        from PySide6.QtWidgets import QApplication
        from PySide6.QtTest import QTest
        from gui.processing import ProcessingPanel
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        panel = ProcessingPanel(engine.processing, lambda action: action())
        self.addCleanup(panel.close)
        inputs = panel.inputs
        self.assertTrue(panel.lock_scale.isChecked())
        with patch.object(engine, 'send') as send:
            inputs['geo']['scale_x'].setValue(1.2)
            QTest.qWait(80)
            inputs['geo']['angle'].setValue(12.3)
            QTest.qWait(80)
            inputs['geo']['scale_x'].setValue(1.7)
            self.assertEqual(inputs['geo']['scale_y'].value(), 1.7)
            QTest.qWait(150)
            send.assert_not_called()
            QTest.qWait(100)
            send.assert_called_once_with('geo set 0 123 1700 1700 0 0 0 0', 'cr')
            panel.lock_scale.setChecked(False)
            inputs['geo']['scale_y'].setValue(.65)
            self.assertEqual(inputs['geo']['scale_x'].value(), 1.7)
            QTest.qWait(250)
            self.assertEqual(send.call_args.args[0], 'geo set 0 123 1700 650 0 0 0 0')
            for stage in ('stage1', 'stage2'):
                self.assertEqual(inputs['pix'][stage].count(), 7)
                inputs['pix'][stage].setCurrentIndex(6)
            for key in ('bc', 'gamma_en', 'gray', 'binary', 'invert'):
                inputs['pix'][key].setChecked(True)
            QTest.qWait(250)
            self.assertEqual(send.call_args.args[0], 'pix set 1 256 0 1 1000 6 6 1 1 128 1')
        app.processEvents()
