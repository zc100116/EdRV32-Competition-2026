"""Task T-UI1-R: shared class names, wrapped logs and intact inference footer."""
import os
from pathlib import Path
import re
import sys
import unittest

from tools.debug_tool.core.labels import COCO_NAMES, SOURCE
from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.telemetry import encode

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from telemetry_sim import periodic


class UiRevisionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtWidgets import QApplication
        cls.app = QApplication.instance() or QApplication([])

    def test_names_are_firmware_table_and_painted(self):
        from PySide6.QtGui import QImage
        from PySide6.QtCore import Qt
        from gui.video import DetectionView, detection_label
        names = re.findall(r'"([^"]+)"', SOURCE.read_text().split(
            'class_names[80] = {', 1)[1].split('};', 1)[0])
        self.assertEqual(list(COCO_NAMES), names)
        self.assertEqual(len(COCO_NAMES), 80)
        self.assertEqual([COCO_NAMES[i] for i in (0, 2, 5)], ['person', 'car', 'bus'])
        view = DetectionView()
        view.setAttribute(Qt.WA_DeleteOnClose)
        self.addCleanup(self.dispose, view)
        view.set_image(QImage(1280, 720, QImage.Format_RGB16),
                       [(20, 30, 100, 200, i, 900) for i in (0, 2, 5)])
        view.show()
        self.app.processEvents()
        self.assertEqual([detection_label(i, 900) for i in (0, 2, 5)],
                         ['person · 0.900', 'car · 0.900', 'bus · 0.900'])
        self.assertFalse(view.grab().isNull())

    def dispose(self, widget):
        from PySide6.QtCore import QCoreApplication, QEvent
        widget.close()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
        self.app.processEvents()

    def test_long_log_wrap_and_footer_both_sizes(self):
        from gui.app import MainWindow
        from PySide6.QtWidgets import QPlainTextEdit
        window = MainWindow(SerialEngine())
        from PySide6.QtCore import Qt
        window.setAttribute(Qt.WA_DeleteOnClose)
        self.addCleanup(self.dispose, window)
        window.show()
        for width, height in ((1366, 768), (1920, 1080)):
            window.resize(width, height)
            console = window.soc
            window.engine.telemetry.ingest(encode(periodic(1, 1, 100)))
            console.refresh()
            console.log.appendPlainText('Long log path / ' + 'abcdef' * 150)
            self.app.processEvents()
            self.assertEqual(console.log.lineWrapMode(), QPlainTextEdit.WidgetWidth)
            self.assertGreater(console.log.document().lastBlock().layout().lineCount(), 1)
            self.assertEqual(console.log.horizontalScrollBar().maximum(), 0)
            text = console.monitor_note
            self.assertFalse(text.wordWrap())
            self.assertGreaterEqual(text.width(), text.fontMetrics().horizontalAdvance(text.text()))
            self.assertGreaterEqual(text.y(), console.realtime.geometry().bottom())
            self.assertLess(text.geometry().bottom(), console.monitor_card.height())
