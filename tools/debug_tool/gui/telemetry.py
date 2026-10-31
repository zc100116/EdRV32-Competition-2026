"""telemetry.py — B2 design 3.6 DDR dashboard; host/Qt UI thread.

Native QPainter charts render a 60-second memory-bus timeline without dependencies.
Serial commands and UDP reception use the shared engine.
"""

from PySide6.QtCore import Qt, QPointF, QRectF
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QWidget

COLORS = ['#4085ed', '#24b5a3', '#9c7ce5', '#e9a24b', '#e47a9e', '#67a6bc', '#718096']


class Timeline(QWidget):
    def __init__(self, utilization=False):
        super().__init__()
        self.setMinimumHeight(110 if utilization else 220)
        self.utilization = utilization
        self.rows = []
        self.mode = 2

    def paintEvent(self, event):
        painter = QPainter(self)
        font = painter.font()
        font.setPixelSize(11)
        painter.setFont(font)
        painter.setRenderHint(QPainter.Antialiasing)
        bounds = QRectF(48, 14, self.width() - 66, self.height() - 54)
        painter.fillRect(self.rect(), QColor('#ffffff'))
        top = 1 if self.utilization else 4.4
        end = self.rows[-1]['time_s'] if self.rows else 60
        start = end - 60

        def point(t, value):
            return QPointF(bounds.left() + (t - start) / 60 * bounds.width(),
                           bounds.bottom() - value / top * bounds.height())

        painter.setPen(QColor('#9aa6b5'))
        painter.drawText(0, 12, '%' if self.utilization else 'GB/s')
        for value in ([0, .5, 1] if self.utilization else [0, 1, 2, 3, 4]):
            y = point(start, value).y()
            painter.setPen(QPen(QColor('#edf0f5'), 1))
            painter.drawLine(QPointF(bounds.left(), y), QPointF(bounds.right(), y))
            painter.setPen(QColor('#8a98aa'))
            label = f'{value * 100:.0f}' if self.utilization else str(value)
            painter.drawText(QRectF(0, y - 8, 40, 16), Qt.AlignRight, label)
        for second in range(0, 61, 10):
            x = point(start + second, 0).x()
            painter.drawText(QRectF(x - 24, bounds.bottom() + 8, 48, 20),
                             Qt.AlignCenter, f'{second - 60} s')
        if self.rows:
            # Plot at pixel resolution; the core retains every sample for CSV and statistics.
            step = max(1, len(self.rows) // int(bounds.width()))
            rows = self.rows[::step]
            if rows[-1] is not self.rows[-1]:
                rows.append(self.rows[-1])
            if self.utilization:
                path = QPainterPath(point(rows[0]['time_s'], rows[0]['utilization']))
                for row in rows[1:]:
                    path.lineTo(point(row['time_s'], row['utilization']))
                painter.setPen(QPen(QColor('#24b5a3'), 2))
                painter.drawPath(path)
            else:
                cumulative = [0.0] * len(rows)
                # Read and write are separate stacked layers, paired by port color.
                for port in range(7):
                    directions = (['read_Bps'] if self.mode == 0 else ['write_Bps']
                                  if self.mode == 1 else ['read_Bps', 'write_Bps'])
                    for direction in directions:
                        upper = [base + row['ports'][port][direction] / 1e9
                                 for base, row in zip(cumulative, rows)]
                        path = QPainterPath(point(rows[0]['time_s'], cumulative[0]))
                        for row, value in zip(rows, upper):
                            path.lineTo(point(row['time_s'], value))
                        for row, value in reversed(list(zip(rows, cumulative))):
                            path.lineTo(point(row['time_s'], value))
                        path.closeSubpath()
                        color = QColor(COLORS[port])
                        color.setAlpha(205 if direction == 'read_Bps' else 120)
                        painter.fillPath(path, color)
                        cumulative = upper
                for value, text, color in [(4.0, '4.0 理论', '#9aa6b5'),
                                            (2.6, '2.6 规划有效', '#d4963c')]:
                    y = point(start, value).y()
                    painter.setPen(QPen(QColor(color), 1, Qt.DashLine))
                    painter.drawLine(QPointF(bounds.left(), y), QPointF(bounds.right(), y))
                    painter.drawText(QPointF(bounds.right() - 100, y - 5), text)
            scene = None
            for row in self.rows:
                if scene is not None and row['scene'] != scene:
                    x = point(row['time_s'], 0).x()
                    painter.setPen(QPen(QColor('#8793a6'), 1, Qt.DotLine))
                    painter.drawLine(QPointF(x, bounds.top()), QPointF(x, bounds.bottom()))
                    painter.drawText(QPointF(x + 4, bounds.top() + 30), f"S{row['scene']}")
                scene = row['scene']
        else:
            painter.setPen(QColor('#8a98aa'))
            painter.drawText(bounds, Qt.AlignCenter, '等待监控数据 · 或打开 CSV 回放')


class Histogram(QWidget):
    def __init__(self):
        super().__init__()
        self.record = None
        self.setMinimumHeight(120)

    def paintEvent(self, event):
        painter = QPainter(self)
        font = painter.font()
        font.setPixelSize(11)
        painter.setFont(font)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QColor('#8793a6'))
        if self.record is None:
            painter.drawText(self.rect(), Qt.AlignCenter, '等待 type 2 · 探针默认关闭')
            return
        counts = [self.record[f'hist{i}'] for i in range(16)]
        peak = max(counts) or 1
        width = (self.width() - 20) / 16
        for i, count in enumerate(counts):
            height = count / peak * (self.height() - 42)
            painter.fillRect(QRectF(10 + i * width, self.height() - 28 - height,
                                   width - 3, height), QColor('#9c7ce5'))
            if i in (0, 4, 8, 12, 15):
                painter.drawText(QRectF(i * width - 4, self.height() - 24, 40, 20),
                                 Qt.AlignCenter, '15+' if i == 15 else str(i))
