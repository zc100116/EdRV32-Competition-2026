"""T-DDRPLOT: interactive DDR curves and the shared retained time window."""

import os
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

os.environ['QT_QPA_PLATFORM'] = 'offscreen'

from PySide6.QtCore import QCoreApplication, QEvent, QPoint, QPointF, Qt
from PySide6.QtGui import QPainter, QWheelEvent
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from gui.telemetry import Timeline


class TimelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.chart = Timeline()
        self.chart.setAttribute(Qt.WA_DeleteOnClose)
        self.chart.resize(700, 260)
        self.chart.rows = [
            {'time_s': float(t), 'scene': 1, 'utilization': .3,
             'ports': [{'read_Bps': (p + 1) * 100_000_000, 'write_Bps': 0}
                       for p in range(7)]}
            for t in range(61)]
        self.chart.show()
        self.app.processEvents()
        self.addCleanup(self.dispose, self.chart)

    def dispose(self, widget):
        widget.close()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
        self.app.processEvents()

    def wheel(self, delta):
        center = self.chart.plot_bounds().center()
        event = QWheelEvent(center, QPointF(self.chart.mapToGlobal(center.toPoint())),
                            QPoint(), QPoint(0, delta), Qt.NoButton, Qt.NoModifier,
                            Qt.NoScrollPhase, False)
        self.app.sendEvent(self.chart, event)

    def test_click_legend_excludes_curve_from_painter(self):
        QTest.mouseClick(self.chart, Qt.LeftButton,
                         pos=self.chart.legend_rects()[2].center().toPoint())
        painter = Mock()
        self.chart.draw_curves(painter)
        self.assertFalse(self.chart.visible[2])
        self.assertEqual(painter.drawPath.call_count, 6)
        # Compare actual drawn geometry, so a hidden curve cannot remain in the plot.
        paths = [call.args[0] for call in painter.drawPath.call_args_list]
        self.assertNotIn(self.chart.curve_path(2), paths)
        QTest.mouseClick(self.chart, Qt.LeftButton,
                         pos=self.chart.legend_rects()[2].center().toPoint())
        self.assertTrue(self.chart.visible[2])

    def test_hover_legend_and_curve_highlights_and_draws_last(self):
        QTest.mouseMove(self.chart, self.chart.legend_rects()[3].center().toPoint())
        self.assertEqual(self.chart.highlight, 3)
        self.assertGreater(self.chart.pen(3).widthF(), self.chart.pen(2).widthF())
        self.assertGreater(self.chart.pen(3).color().alpha(), self.chart.pen(2).color().alpha())
        painter = Mock()
        self.chart.draw_curves(painter)
        self.assertEqual(painter.drawPath.call_args.args[0], self.chart.curve_path(3))
        point = self.chart.point(self.chart.rows[30], 4).toPoint()
        QTest.mouseMove(self.chart, point)
        self.assertEqual(self.chart.highlight, 4)
        self.assertEqual(self.chart.hover, QPointF(point))

    def test_hover_draws_time_line_and_sample_values(self):
        self.chart.rows[30]['ports'][0]['read_Bps'] = 900_000_000
        pos = self.chart.plot_bounds().center().toPoint()
        QTest.mouseMove(self.chart, pos)
        texts, lines = [], []

        class RecordingPainter(QPainter):
            def drawText(self, *args):
                texts.append(args[-1])
                return super().drawText(*args)

            def drawLine(self, *args):
                lines.append(args)
                return super().drawLine(*args)

        with patch('gui.telemetry.QPainter', RecordingPainter):
            self.chart.grab()
        self.assertIn('DISP 0.900', texts)
        self.assertIn('-30.00 s', texts)
        bounds = self.chart.plot_bounds()
        self.assertIn((QPointF(pos.x(), bounds.top()),
                       QPointF(pos.x(), bounds.bottom())), lines)

    def test_double_click_legend_solo_then_all(self):
        pos = self.chart.legend_rects()[4].center().toPoint()
        QTest.mouseDClick(self.chart, Qt.LeftButton, pos=pos)
        self.assertEqual(self.chart.visible, [False, False, False, False, True, False, False])
        QTest.mouseDClick(self.chart, Qt.LeftButton, pos=pos)
        self.assertEqual(self.chart.visible, [True] * 7)

    def test_drag_moves_both_charts_and_pauses_until_double_click(self):
        other = Timeline(True, axis=self.chart.axis)
        other.setAttribute(Qt.WA_DeleteOnClose)
        other.rows = self.chart.rows
        self.addCleanup(self.dispose, other)
        self.wheel(480)
        before = self.chart.axis.window(self.chart.rows)
        center = self.chart.plot_bounds().center().toPoint()
        QTest.mousePress(self.chart, Qt.LeftButton, pos=center)
        QTest.mouseMove(self.chart, center + QPoint(80, 0))
        QTest.mouseRelease(self.chart, Qt.LeftButton, pos=center + QPoint(80, 0))
        moved = self.chart.axis.window(self.chart.rows)
        self.assertLess(moved[0], before[0])
        self.assertAlmostEqual(moved[1] - moved[0], before[1] - before[0])
        self.assertEqual(other.axis.window(other.rows), moved)
        self.chart.rows.append(dict(self.chart.rows[-1], time_s=61.0))
        self.assertEqual(self.chart.axis.window(self.chart.rows), moved)
        self.assertIsNotNone(self.chart.axis.end)
        QTest.mouseDClick(self.chart, Qt.LeftButton, pos=center)
        self.assertIsNone(self.chart.axis.end)
        self.assertEqual(self.chart.axis.window(self.chart.rows), (1.0, 61.0))
        self.assertEqual(other.axis.span, 60)

    def test_zoom_limits_and_retained_data_bounds(self):
        self.wheel(12000)
        self.assertEqual(self.chart.axis.span, 5)
        self.wheel(-24000)
        self.assertEqual(self.chart.axis.span, 60)
        self.assertIsNotNone(self.chart.axis.end)
        self.chart.axis.end = -100
        self.assertEqual(self.chart.axis.window(self.chart.rows), (0, 60))
        self.chart.rows = self.chart.rows[40:]
        self.assertEqual(self.chart.axis.window(self.chart.rows), (40, 60))
        self.chart.axis.end = 100
        self.assertEqual(self.chart.axis.window(self.chart.rows), (40, 60))

    def test_read_write_mode_and_legend_fit_both_window_sizes(self):
        from tools.debug_tool.core.engine import SerialEngine
        from gui.app import MainWindow
        window = MainWindow(SerialEngine())
        window.setAttribute(Qt.WA_DeleteOnClose)
        self.addCleanup(self.dispose, window)
        window.show()
        for width, height in ((1366, 768), (1920, 1080)):
            window.resize(width, height)
            self.app.processEvents()
            chart = window.soc.bandwidth
            self.assertIs(chart.axis, window.soc.utilization.axis)
            for rect in chart.legend_rects():
                self.assertTrue(chart.rect().contains(rect.toRect()))
                self.assertGreater(rect.width() - 20,
                                   chart.fontMetrics().horizontalAdvance('DISP 4.000'))
            self.assertGreater(chart.plot_bounds().height(), 0)
            self.assertEqual((window.width(), window.height()), (width, height))
        row = self.chart.rows[0]
        row['ports'][0]['write_Bps'] = 50_000_000
        for mode, value in ((0, .1), (1, .05), (2, .15)):
            self.chart.mode = mode
            self.assertAlmostEqual(self.chart.value(row, 0), value)
