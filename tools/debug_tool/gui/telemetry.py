"""telemetry.py — B2 design 3.6 DDR dashboard; host/Qt UI thread.

Native QPainter charts render a 60-second memory-bus timeline without dependencies.
Serial commands and UDP reception use the shared engine.
"""

from bisect import bisect_left, bisect_right
from math import ceil, log10

from PySide6.QtCore import QObject, Signal, Qt, QPointF, QRectF
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QPushButton, QWidget

COLORS = ['#4085ed', '#24b5a3', '#9c7ce5', '#e9a24b', '#e47a9e', '#67a6bc', '#718096']


class TimeAxis(QObject):
    """The two charts share navigation, while samples remain owned by telemetry."""
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.span = 60.0
        self.end = None

    def window(self, rows):
        latest = rows[-1]['time_s'] if rows else 60.0
        oldest = rows[0]['time_s'] if rows else 0.0
        span = min(self.span, latest - oldest) if len(rows) > 1 else self.span
        end = latest if self.end is None else min(latest, max(oldest + span, self.end))
        return end - span, end

    def restore(self):
        self.span, self.end = 60.0, None
        self.changed.emit()


class Timeline(QWidget):
    scale_changed = Signal()

    def __init__(self, utilization=False, axis=None):
        super().__init__()
        self.setMinimumHeight(110 if utilization else 220)
        self.setMouseTracking(True)
        self.setToolTip('单击图例显示或隐藏，双击图例只看该端口或恢复全部；'
                        '悬停查看读数，左右拖动平移，滚轮缩放时间，Ctrl + 滚轮缩放带宽；'
                        '双击图内恢复时间跟随和自动纵轴。')
        self.utilization = utilization
        self.axis = axis if axis is not None else TimeAxis()
        self.axis.changed.connect(self.update)
        self.rows = []
        self.mode = 2
        self.manual_top = None
        self.visible = [True] * (1 if utilization else 7)
        self.highlight = None
        self.solo = None
        self.hover = None
        self.drag = None

    def y_top(self):
        if self.utilization:
            return 1.0
        if self.manual_top is not None:
            return self.manual_top
        start, end = self.axis.window(self.rows)
        peak = max((self.value(row, port) for row in self.rows
                    if start <= row['time_s'] <= end
                    for port, visible in enumerate(self.visible) if visible), default=0)
        if peak == 0:
            return 1.0
        power = 10 ** (ceil(log10(peak)) - 1)
        return next(factor * power for factor in (1, 2, 5, 10) if factor * power >= peak)

    def set_y_top(self, top):
        self.manual_top = top
        self.scale_changed.emit()
        self.update()

    def scale_button(self):
        button = QPushButton()

        def refresh():
            button.setText('满量程' if self.manual_top is None else '自动')
        button.clicked.connect(lambda: self.set_y_top(
            4.4 if self.manual_top is None else None))
        self.scale_changed.connect(refresh)
        refresh()
        button.setToolTip('切换带宽纵轴：自动缩放 / 满量程 0–4.4 GB/s')
        return button

    def plot_bounds(self):
        return QRectF(48, 56, self.width() - 66, self.height() - 80)

    def legend_rects(self):
        columns = 4
        width = (self.width() - 8) / columns
        return [QRectF(4 + i % columns * width, 2 + i // columns * 20, width, 20)
                for i in range(len(self.visible))]

    def legend_at(self, pos):
        return next((i for i, rect in enumerate(self.legend_rects()) if rect.contains(pos)),
                    None)

    def value(self, row, port):
        if self.utilization:
            return row['utilization']
        data = row['ports'][port]
        return ((data['read_Bps'] if self.mode != 1 else 0) +
                (data['write_Bps'] if self.mode != 0 else 0)) / 1e9

    def point(self, row, port, top=None):
        bounds = self.plot_bounds()
        start, end = self.axis.window(self.rows)
        return QPointF(bounds.left() + (row['time_s'] - start) / (end - start) *
                       bounds.width(), bounds.bottom() - self.value(row, port) /
                       (self.y_top() if top is None else top) * bounds.height())

    def plot_rows(self):
        start, end = self.axis.window(self.rows)
        # Keep the adjacent samples so clipped lines reach both viewport edges.
        first = max(0, bisect_left([r['time_s'] for r in self.rows], start) - 1)
        last = bisect_right([r['time_s'] for r in self.rows], end) + 1
        rows = self.rows[first:last]
        step = max(1, len(rows) // int(self.plot_bounds().width()))
        sampled = rows[::step]
        if rows and sampled[-1] is not rows[-1]:
            sampled.append(rows[-1])
        return sampled

    def curve_path(self, port, top=None):
        path = QPainterPath()
        rows = self.plot_rows()
        top = self.y_top() if top is None else top
        if rows:
            path.moveTo(self.point(rows[0], port, top))
            for row in rows[1:]:
                path.lineTo(self.point(row, port, top))
        return path

    def pen(self, port):
        color = QColor(COLORS[1 if self.utilization else port])
        if self.highlight is not None and self.highlight != port:
            color.setAlpha(45)
        return QPen(color, 3 if self.highlight == port else 1.6)

    def draw_curves(self, painter):
        order = [i for i, visible in enumerate(self.visible) if visible]
        if self.highlight in order:
            order.remove(self.highlight)
            order.append(self.highlight)
        top = self.y_top()
        for port in order:
            painter.setPen(self.pen(port))
            painter.drawPath(self.curve_path(port, top))

    def mousePressEvent(self, event):
        if event.button() != Qt.LeftButton:
            return
        port = self.legend_at(event.position())
        if port is not None:
            self.visible[port] = not self.visible[port]
            self.update()
        elif self.plot_bounds().contains(event.position()) and self.rows:
            start, end = self.axis.window(self.rows)
            self.drag = (event.position().x(), end, end - start)

    def mouseMoveEvent(self, event):
        pos = event.position()
        bounds = self.plot_bounds()
        if self.drag is not None:
            x, end, span = self.drag
            self.axis.end = end - (pos.x() - x) / bounds.width() * span
            self.axis.end = self.axis.window(self.rows)[1]
            self.axis.changed.emit()
        self.hover = pos if bounds.contains(pos) else None
        self.highlight = self.legend_at(pos)
        if self.hover is not None and self.rows:
            nearest = None
            distance = 7.0
            top = self.y_top()
            for port, visible in enumerate(self.visible):
                if not visible:
                    continue
                points = [self.point(row, port, top) for row in self.plot_rows()]
                for a, b in zip(points, points[1:]):
                    dx, dy = b.x() - a.x(), b.y() - a.y()
                    length = dx * dx + dy * dy
                    fraction = (max(0, min(1, ((pos.x() - a.x()) * dx +
                                              (pos.y() - a.y()) * dy) / length))
                                if length else 0)
                    gap = ((pos.x() - a.x() - fraction * dx) ** 2 +
                           (pos.y() - a.y() - fraction * dy) ** 2) ** .5
                    if gap < distance:
                        distance, nearest = gap, port
            self.highlight = nearest
        self.update()

    def mouseReleaseEvent(self, event):
        self.drag = None

    def mouseDoubleClickEvent(self, event):
        if event.button() != Qt.LeftButton:
            return
        port = self.legend_at(event.position())
        if port is not None:
            if self.solo == port:
                self.visible = [True] * len(self.visible)
                self.solo = None
            else:
                self.visible = [i == port for i in range(len(self.visible))]
                self.solo = port
            self.update()
        elif self.plot_bounds().contains(event.position()):
            self.drag = None
            self.set_y_top(None)
            self.axis.restore()

    def wheelEvent(self, event):
        if not self.plot_bounds().contains(event.position()) or not self.rows:
            return
        if event.modifiers() & Qt.ControlModifier:
            if not self.utilization:
                self.set_y_top(self.y_top() * 1.2 ** (-event.angleDelta().y() / 120))
            event.accept()
            return
        start, end = self.axis.window(self.rows)
        fraction = (event.position().x() - self.plot_bounds().left()) / self.plot_bounds().width()
        anchor = start + fraction * (end - start)
        self.axis.span = max(5.0, min(60.0, self.axis.span * 1.2 **
                                    (-event.angleDelta().y() / 120)))
        span = min(self.axis.span, self.rows[-1]['time_s'] - self.rows[0]['time_s'])
        self.axis.end = anchor + (1 - fraction) * span
        self.axis.end = self.axis.window(self.rows)[1]
        self.axis.changed.emit()
        event.accept()

    def leaveEvent(self, event):
        self.hover = self.highlight = None
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        font = painter.font()
        font.setPixelSize(11)
        painter.setFont(font)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor('#ffffff'))
        bounds = self.plot_bounds()
        start, end = self.axis.window(self.rows)
        latest = self.rows[-1]['time_s'] if self.rows else end
        top = self.y_top()
        readout = self.rows[-1] if self.rows else None
        if self.hover is not None and self.rows:
            time = start + (self.hover.x() - bounds.left()) / bounds.width() * (end - start)
            readout = min(self.rows, key=lambda row: abs(row['time_s'] - time))
        names = ['利用率'] if self.utilization else ['DISP', 'VIN', 'CPU', 'NPU', 'RND', 'GEO', 'ETH']
        for port, rect in enumerate(self.legend_rects()):
            painter.setPen(self.pen(port))
            painter.drawLine(QPointF(rect.left() + 3, rect.center().y()),
                             QPointF(rect.left() + 15, rect.center().y()))
            painter.setPen(QColor('#36465c' if self.visible[port] else '#a0a9b5'))
            value = ('—' if readout is None else
                     f'{self.value(readout, port) * 100:.1f}%' if self.utilization else
                     f'{self.value(readout, port):.3f}')
            font.setStrikeOut(not self.visible[port])
            painter.setFont(font)
            text = f'{names[port]} {value}'
            painter.drawText(rect.adjusted(20, 0, 0, 0), Qt.AlignVCenter, text)
        font.setStrikeOut(False)
        painter.setFont(font)
        painter.setPen(QColor('#8a98aa'))
        painter.drawText(QPointF(0, 49), '%' if self.utilization else 'GB/s')
        for value in ([0, .5, 1] if self.utilization else [top * i / 4 for i in range(5)]):
            y = bounds.bottom() - value / top * bounds.height()
            painter.setPen(QPen(QColor('#edf0f5'), 1))
            painter.drawLine(QPointF(bounds.left(), y), QPointF(bounds.right(), y))
            painter.setPen(QColor('#8a98aa'))
            label = f'{value * 100:.0f}' if self.utilization else f'{value:.3g}'
            painter.drawText(QRectF(0, y - 8, 43, 16), Qt.AlignRight, label)
        if not self.utilization:
            references = ' · '.join(text for value, text in
                                    [(4.0, '理论 4.0'), (2.6, '规划有效 2.6')]
                                    if value > top)
            painter.drawText(QRectF(bounds.left(), 40, bounds.width(), 14),
                             Qt.AlignRight, references + (' GB/s' if references else ''))
        for tick in range(5):
            x = bounds.left() + tick / 4 * bounds.width()
            second = start + tick / 4 * (end - start) - latest
            painter.drawText(QRectF(x - 24, bounds.bottom() + 3, 48, 20),
                             Qt.AlignCenter, f'{second:.0f} s')
        painter.save()
        painter.setClipRect(bounds)
        if self.rows:
            if not self.utilization:
                for value, text, color in [(4.0, '4.0 理论', '#9aa6b5'),
                                            (2.6, '2.6 规划有效', '#d4963c')]:
                    if value > top:
                        continue
                    y = bounds.bottom() - value / top * bounds.height()
                    painter.setPen(QPen(QColor(color), 1, Qt.DashLine))
                    painter.drawLine(QPointF(bounds.left(), y), QPointF(bounds.right(), y))
                    label_y = max(bounds.top() + 12, y - 3)
                    painter.drawText(QPointF(bounds.right() - 85, label_y), text)
            self.draw_curves(painter)
            scene = None
            for row in self.rows:
                if scene is not None and row['scene'] != scene:
                    x = self.point(row, 0).x()
                    painter.setPen(QPen(QColor('#8793a6'), 1, Qt.DotLine))
                    painter.drawLine(QPointF(x, bounds.top()), QPointF(x, bounds.bottom()))
                    painter.drawText(QPointF(x + 4, bounds.top() + 12), f"S{row['scene']}")
                scene = row['scene']
            if self.hover is not None:
                painter.setPen(QPen(QColor('#8793a6'), 1, Qt.DashLine))
                painter.drawLine(QPointF(self.hover.x(), bounds.top()),
                                 QPointF(self.hover.x(), bounds.bottom()))
                painter.drawText(QPointF(bounds.left() + 4, bounds.bottom() - 4),
                                 f"{readout['time_s'] - latest:.2f} s")
        else:
            painter.setPen(QColor('#8a98aa'))
            painter.drawText(bounds, Qt.AlignCenter, '等待监控数据 · 或打开 CSV 回放')
        painter.restore()
        if self.axis.end is not None:
            text = '已暂停跟随，双击恢复'
            rect = QRectF(bounds.left() + 4, bounds.top() + 2, 150, 18)
            painter.fillRect(rect, QColor('#ffffff'))
            painter.setPen(QColor('#98641f'))
            painter.drawText(rect, Qt.AlignVCenter, text)


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
