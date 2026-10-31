"""T-UIMAX: console panel expansion, live updates and scoped Escape handling."""

import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

os.environ['QT_QPA_PLATFORM'] = 'offscreen'
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PySide6.QtCore import QCoreApplication, QEvent, Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QLabel, QPushButton

from core.engine import SerialEngine
from core.telemetry import encode
from gui.app import MainWindow
from telemetry_sim import periodic


class PanelZoomTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.window = MainWindow(SerialEngine())
        self.window.setAttribute(Qt.WA_DeleteOnClose)
        self.window.resize(1366, 768)
        self.window.show()
        self.window._select_page(4)
        self.app.processEvents()
        self.console = self.window.soc

    def tearDown(self):
        self.window.close()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
        self.app.processEvents()

    def test_each_panel_expands_and_restores_original_layout(self):
        console = self.console
        for panel, button in console.panel_buttons.items():
            parent = panel.parentWidget()
            geometry = panel.geometry()
            minimum, maximum = panel.minimumSize(), panel.maximumSize()
            button.click()
            self.app.processEvents()
            self.assertIs(console.expanded_panel, panel)
            self.assertTrue(panel.isVisible())
            self.assertEqual(panel.size(), console.size())
            self.assertTrue(all(not other.isVisible() for other in console.panel_buttons
                                if other is not panel))
            self.assertEqual(button.text(), '复原')
            button.click()
            self.app.processEvents()
            self.assertIsNone(console.expanded_panel)
            self.assertIs(panel.parentWidget(), parent)
            self.assertEqual(panel.geometry(), geometry)
            self.assertEqual(panel.minimumSize(), minimum)
            self.assertEqual(panel.maximumSize(), maximum)
            self.assertEqual(button.text(), '放大')

    def test_title_double_click_escape_and_live_refresh(self):
        console = self.console
        title = next(title for title, panel in console.panel_titles.items()
                     if panel is console.monitor_card)
        QTest.mouseDClick(title, Qt.LeftButton)
        self.app.processEvents()
        self.assertIs(console.expanded_panel, console.monitor_card)
        console.engine.telemetry.ingest(encode(periodic(1, 1, 100)))
        console.refresh()
        self.assertEqual(len(console.bandwidth.rows), 1)
        console.engine.add_entry('sys', '放大期间的日志')
        console.refresh()
        self.assertIn('放大期间的日志', console.log.toPlainText())
        with patch.object(console, '_display') as display:
            QTest.qWait(80)
            self.assertGreaterEqual(display.call_count, 2)
        self.window.rail_group.button(4).setFocus()
        QTest.keyClick(self.window, Qt.Key_Escape)
        self.app.processEvents()
        self.assertIsNone(console.expanded_panel)
        QTest.mouseDClick(title, Qt.LeftButton)
        QTest.mouseDClick(title, Qt.LeftButton)
        self.assertIsNone(console.expanded_panel)

    def test_panel_controls_fit_both_sizes(self):
        console = self.console
        for width, height in ((1366, 768), (1920, 1080)):
            self.window.resize(width, height)
            self.app.processEvents()
            self.assertEqual((self.window.width(), self.window.height()), (width, height))
            for panel in console.panel_buttons:
                for widget in panel.findChildren(QPushButton) + panel.findChildren(QLabel):
                    if widget.isVisible() and not (isinstance(widget, QLabel) and widget.wordWrap()):
                        self.assertGreaterEqual(
                            widget.width(), widget.fontMetrics().horizontalAdvance(widget.text()),
                            widget.text())
