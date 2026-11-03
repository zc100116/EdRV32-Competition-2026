"""P5 8.3 item enable/disable preserves parameters and full reset disables all."""
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.processing import DEFAULTS, pack_process, unpack_process

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


class ProcessingTest(unittest.TestCase):
    def test_block_defaults_and_ranges(self):
        self.assertEqual(len(pack_process(DEFAULTS)), 24)
        self.assertEqual(unpack_process(pack_process(DEFAULTS)), DEFAULTS)
        for values in ({'contrast': 513}, {'gamma_tenths': 2}, {'scale_percent': 49}):
            with self.assertRaises(ValueError):
                pack_process(dict(DEFAULTS, **values))

    def test_switches_preserve_values_defaults_and_debounce(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtWidgets import QApplication
        from PySide6.QtTest import QTest
        from gui.processing import ProcessingPanel
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        panel = ProcessingPanel(engine.processing, lambda action: action())
        self.addCleanup(panel.close)
        with patch.object(engine.processing, 'send') as send:
            panel.switches[0].setChecked(True)
            panel.inputs['brightness'].setValue(100)
            QTest.qWait(80)
            panel.inputs['contrast'].setValue(512)
            QTest.qWait(150)
            send.assert_not_called()
            QTest.qWait(100)
            self.assertEqual(send.call_args.args[0]['enabled'], 1)
            panel.switches[0].setChecked(False)
            QTest.qWait(250)
            self.assertEqual(send.call_args.args[0]['brightness'], 100)
            self.assertEqual(send.call_args.args[0]['enabled'], 0)
            panel.reset(0)
            self.assertEqual(send.call_args.args[0]['brightness'], 0)
            self.assertEqual(send.call_args.args[0]['contrast'], 256)
            panel.reset()
            self.assertEqual(send.call_args.args[0], DEFAULTS)
        app.processEvents()
