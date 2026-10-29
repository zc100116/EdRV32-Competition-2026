"""telemetry.py — B2 design 3.6 DDR dashboard; host/Qt UI thread.

Native QPainter charts render a 60-second memory-bus timeline without dependencies.
Serial commands and UDP reception use the shared engine.
"""

import time
from PySide6.QtCore import Qt, QPointF, QRectF
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (
    QComboBox, QFileDialog, QFrame, QGridLayout, QHBoxLayout, QLabel,
    QPushButton, QSpinBox, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
    QHeaderView,
)
from core.telemetry import PORTS, encode

COLORS = ['#4085ed', '#24b5a3', '#9c7ce5', '#e9a24b', '#e47a9e', '#67a6bc', '#718096']


def card(title):
    frame = QFrame()
    frame.setObjectName('card')
    layout = QVBoxLayout(frame)
    label = QLabel(title)
    label.setObjectName('cardTitle')
    layout.addWidget(label)
    return frame, layout


class Timeline(QWidget):
    def __init__(self, utilization=False):
        super().__init__()
        self.setMinimumHeight(110 if utilization else 220)
        self.utilization = utilization
        self.rows = []
        self.mode = 2

    def paintEvent(self, event):
        painter = QPainter(self)
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
            painter.drawText(bounds, Qt.AlignCenter, '等待 WIN 3 监控数据 · 或打开 CSV 回放')


class Histogram(QWidget):
    def __init__(self):
        super().__init__()
        self.record = None
        self.setMinimumHeight(120)

    def paintEvent(self, event):
        painter = QPainter(self)
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


class TelemetryPanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine = engine
        self.toast = toast
        self.setMinimumSize(960, 710)
        self.paused = False
        self.replay = []
        self.replay_time = 0
        self.last_tick = time.monotonic()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 0, 0, 0)
        header = QHBoxLayout()
        title = QLabel('DDR 监控   /   MEMORY BUS')
        title.setStyleSheet('font-size:20px;font-weight:700;color:#24344b')
        header.addWidget(title)
        header.addStretch()
        self.mode = QComboBox()
        self.mode.addItems(['只看读', '只看写', '读写合计'])
        self.mode.setCurrentIndex(2)
        self.mode.currentIndexChanged.connect(self._mode)
        header.addWidget(self.mode)
        self.pause = QPushButton('暂停')
        self.pause.clicked.connect(self._pause)
        header.addWidget(self.pause)
        for label, action in [('清空', self._clear), ('导出 CSV', self._export),
                              ('打开 CSV 回放', self._open)]:
            button = QPushButton(label)
            button.clicked.connect(action)
            header.addWidget(button)
        layout.addLayout(header)
        self.source = QLabel('WIN 3 · clk_mem 125 MHz · 60 s 滚动窗口 · 读深色 / 写浅色')
        self.source.setStyleSheet('color:#8995a7')
        layout.addWidget(self.source)
        receiver = QHBoxLayout()
        receiver.addWidget(QLabel('PC UDP 端口'))
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        self.port.setValue(6000)
        receiver.addWidget(self.port)
        self.listen = QPushButton('开始监听')
        self.listen.clicked.connect(self._listen)
        receiver.addWidget(self.listen)
        self.rx_status = QLabel('未监听')
        receiver.addWidget(self.rx_status, 1)
        layout.addLayout(receiver)
        metrics = QHBoxLayout()
        self.metrics = {}
        for key, title in [('util', 'DDR 利用率'), ('npu', 'NPU 推理'),
                           ('post', 'CPU 后处理'), ('fps', '检测帧率 / 框数'), ('loss', '丢失记录')]:
            frame, box = card(title)
            value = QLabel('—')
            value.setStyleSheet('font-size:25px;font-weight:650;color:#283b55')
            box.addWidget(value)
            self.metrics[key] = value
            metrics.addWidget(frame)
        layout.addLayout(metrics)
        frame, box = card('各端口带宽 · GB/s')
        self.bandwidth = Timeline()
        box.addWidget(self.bandwidth, 1)
        legend = QHBoxLayout()
        for name, color in zip(PORTS, COLORS):
            label = QLabel('● ' + name)
            label.setStyleSheet(f'color:{color};font-size:11px')
            legend.addWidget(label)
        box.addLayout(legend)
        layout.addWidget(frame, 3)
        lower = QHBoxLayout()
        frame, box = card('DDR 利用率 / 场景切换')
        self.utilization = Timeline(True)
        box.addWidget(self.utilization)
        self.rt_labels = []
        realtime = QHBoxLayout()
        for title in ('DISP 读空', 'VIN CH0 溢出', 'VIN CH2 溢出'):
            value = QLabel(title + '\n0')
            value.setAlignment(Qt.AlignCenter)
            value.setStyleSheet('color:#64748b;background:#f5f8fc;border-radius:6px;padding:5px')
            realtime.addWidget(value)
            self.rt_labels.append((title, value))
        box.addLayout(realtime)
        box.addStretch()
        lower.addWidget(frame, 1)
        frame, box = card('读延迟直方图')
        hint = QLabel('探针占用 P6 带宽')
        hint.setStyleSheet('color:#8c6cc3')
        box.addWidget(hint)
        self.hist = Histogram()
        box.addWidget(self.hist, 1)
        self.hist_info = QLabel('格编号 0–15 · 单位 clk_mem 周期\n最后一格收纳更大的延迟')
        self.hist_info.setWordWrap(True)
        self.hist_info.setStyleSheet('color:#8995a7;font-size:11px')
        box.addWidget(self.hist_info)
        lower.addWidget(frame, 1)
        frame, box = card('端口等待与实时性 · 周期 / 次')
        self.table = QTableWidget(7, 4)
        self.table.setHorizontalHeaderLabels(['端口', '平均等待', '最长等待', '紧急授权'])
        self.table.verticalHeader().hide()
        self.table.verticalHeader().setDefaultSectionSize(25)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setStyleSheet('QTableWidget{border:0;gridline-color:#edf0f5}')
        for i, name in enumerate(PORTS):
            for j, text in enumerate([name, '—', '—', '0']):
                self.table.setItem(i, j, QTableWidgetItem(text))
        box.addWidget(self.table)
        lower.addWidget(frame, 2)
        layout.addLayout(lower, 3)
        self.error = QLabel('')
        self.error.setStyleSheet('color:#d24b5c')
        layout.addWidget(self.error)

    def _listen(self):
        try:
            if self.engine.ethernet.status()['rx']['active']:
                self.engine.ethernet.stop_receive()
            else:
                self.replay = []
                self.engine.ethernet.start_receive(self.port.value())
                self.source.setText('WIN 3 · clk_mem 125 MHz · 60 s 滚动窗口 · 读深色 / 写浅色')
        except (OSError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)

    def _mode(self, index):
        self.bandwidth.mode = index
        self.bandwidth.update()

    def _pause(self):
        self.paused = not self.paused
        self.pause.setText('继续' if self.paused else '暂停')

    def _clear(self):
        self.replay = []
        self.engine.telemetry.clear()
        self.refresh(force=True)

    def _export(self):
        path, _ = QFileDialog.getSaveFileName(self, '导出监控数据', 'telemetry.csv', 'CSV (*.csv)')
        if path:
            try:
                self.engine.telemetry.export_csv(path)
            except OSError as exc:
                self.toast.show_message(str(exc), error=True)

    def _open(self):
        path, _ = QFileDialog.getOpenFileName(self, '回放监控数据', '', 'CSV (*.csv)')
        if path:
            try:
                self.engine.ethernet.stop_receive()
                self.engine.telemetry.load_csv(path)
                self.replay = list(self.engine.telemetry.records)
                self.engine.telemetry.clear()
                self.replay_time = (self.replay[0]['mtime'] / self.replay[0]['clk_sys_hz']
                                    if self.replay else 0)
                self.paused = False
                self.pause.setText('暂停')
                self.source.setText(f'CSV 回放 · {path}')
                self.last_tick = time.monotonic()
            except (OSError, ValueError) as exc:
                self.toast.show_message(str(exc), error=True)

    def refresh(self, force=False):
        rx = self.engine.ethernet.status()['rx']
        self.listen.setText('停止监听' if rx['active'] else '开始监听')
        self.rx_status.setText(f"UDP {rx.get('localPort', self.port.value())} · "
                               f"{rx['packets']} 包" +
                               (f" · 错误: {rx['error']}" if rx['error'] else ''))
        now = time.monotonic()
        elapsed = now - self.last_tick
        self.last_tick = now
        if self.paused and not force:
            return
        if self.replay:
            self.replay_time += elapsed
            while (self.replay and self.replay[0]['mtime'] / self.replay[0]['clk_sys_hz']
                   <= self.replay_time):
                self.engine.telemetry.ingest(encode(self.replay.pop(0)))
        history, state = self.engine.telemetry.snapshot()
        self.bandwidth.rows = history
        self.utilization.rows = history
        self.bandwidth.update()
        self.utilization.update()
        self.hist.record = state['histogram']
        self.hist.update()
        histogram = state['histogram']
        if histogram:
            self.hist_info.setText(f"格宽 {histogram['hist_width']} 周期 · "
                                   f"读 {histogram['read_cnt']} 次 · "
                                   f"min/max {histogram['lat_min']}/{histogram['lat_max']}")
        self.metrics['loss'].setText(str(state['lost']))
        self.metrics['loss'].setStyleSheet(
            f"font-size:25px;color:{'#d24b5c' if state['lost'] else '#283b55'}")
        self.error.setText(f"协议错误 {state['errors']} · {state['error']}" if state['error'] else '')
        row = state['latest']
        if not row:
            for key in ('util', 'npu', 'post', 'fps'):
                self.metrics[key].setText('—')
            self._realtime([0, 0, 0])
            self.hist_info.setText('格编号 0–15 · 单位 clk_mem 周期\n最后一格收纳更大的延迟')
            for i in range(7):
                for j in range(1, 4):
                    self.table.item(i, j).setText('—' if j < 3 else '0')
                    self.table.item(i, j).setForeground(QColor('#64748b'))
            return
        self.metrics['util'].setText(f"{row['utilization']:.1%}")
        self.metrics['npu'].setText(f"{row['npu_ms']:.1f} ms")
        self.metrics['post'].setText(f"{row['post_ms']:.1f} ms")
        recent = [sample for sample in history if sample['time_s'] > row['time_s'] - 1]
        fps = sum(sample['npu_completed'] for sample in recent) * 125e6 / sum(
            sample['window_cyc'] for sample in recent)
        self.metrics['fps'].setText(f"{fps:.1f} / {row['boxes']}")
        self.metrics['fps'].setToolTip('最近 1 秒的完成推理数 / 精确窗口时长')
        values = [row['disp_underflow'], row['vin_ch0_overflow'], row['vin_ch2_overflow']]
        self._realtime(values)
        for i, port in enumerate(row['ports']):
            for j, text in enumerate([f"{port['wait_avg']:.1f}", str(port['wait_max']),
                                      str(port['urg_cnt'])], 1):
                self.table.item(i, j).setText(text)
            self.table.item(i, 3).setForeground(
                QColor('#d24b5c' if port['urg_cnt'] else '#64748b'))

    def _realtime(self, values):
        for (title, label), value in zip(self.rt_labels, values):
            label.setText(f'{title}\n{value}')
            color = '#d24b5c' if value else '#64748b'
            background = '#fff0f2' if value else '#f5f8fc'
            label.setStyleSheet(f'color:{color};background:{background};'
                               'border-radius:6px;padding:5px;font-size:11px')


class ScenePanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        layout = QVBoxLayout(self)
        frame, box = card('场景控制 · UART MENU')
        box.addWidget(QLabel('在 scenes.json 填入 B2-4 最终菜单命令。采样率模板使用 {rate}。'))
        self.rate = QSpinBox()
        self.rate.setRange(10, 1000)
        self.rate.setValue(100)
        self.rate.setSuffix(' Hz')
        box.addWidget(self.rate)
        grid = QGridLayout()
        mapping = [(key, item) for key, item in engine.scenes.mapping().items()
                   if not key.startswith('output_') and key != 'video_fps']
        for index, (key, item) in enumerate(mapping):
            button = QPushButton(item['label'])
            button.clicked.connect(lambda checked=False, name=key: self._send(engine, toast, name))
            grid.addWidget(button, index // 3, index % 3)
        box.addLayout(grid)
        box.addWidget(QLabel('延迟探针默认关闭；开启后占用 P6 带宽。场景标记以板子上报为准。'))
        layout.addWidget(frame)
        layout.addStretch()

    def _send(self, engine, toast, name):
        try:
            engine.scenes.send(name, self.rate.value())
        except (OSError, ValueError, RuntimeError) as exc:
            toast.show_message(str(exc), error=True)
