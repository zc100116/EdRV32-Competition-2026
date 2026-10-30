"""soc_console.py — SoC console design 4.1–4.5; host Qt thread.

One canvas and one board session join programming, scene controls and monitoring.
Fixed side columns scroll vertically while the central canvas yields space.
"""

import json
from pathlib import Path
import struct
import threading
import time

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QImage
from PySide6.QtWidgets import (
    QComboBox, QFileDialog, QFormLayout, QFrame, QGridLayout, QHBoxLayout,
    QHeaderView, QLabel, QLineEdit, QPlainTextEdit, QProgressBar, QPushButton,
    QScrollArea, QSizePolicy, QSpinBox, QSplitter, QStackedWidget, QTableWidget,
    QTableWidgetItem, QVBoxLayout, QWidget,
)
from core.engine import fmt_ts
from core.session import PROJECTS
from core.telemetry import encode
from gui.program import ProgramPanel
from gui.telemetry import COLORS, Histogram, Timeline
from gui.video import DetectionView

STYLE = """
QWidget#socConsole { background: #f3f5f8; }
QWidget#socConsole, QWidget#socConsole QLabel { font-size: 12px; color: #33404d; }
QWidget#socConsole QLabel[role="title"] {
    font-size: 14px; font-weight: 700; color: #2f6bff; letter-spacing: 0px;
}
QWidget#socConsole QLabel[role="note"] { font-size: 11px; color: #7a8b9d; }
QWidget#socConsole QLabel[role="number"] {
    font-family: "DejaVu Sans Mono", "Consolas", monospace; font-size: 12px;
}
QWidget#socConsole QPushButton { font-size: 12px; padding: 5px 8px; }
QWidget#socConsole QLineEdit, QWidget#socConsole QComboBox,
QWidget#socConsole QSpinBox { font-size: 12px; min-height: 23px; padding: 3px 6px; }
QWidget#socConsole QProgressBar { min-height: 7px; max-height: 7px; }
QWidget#socConsole QTabWidget::pane { border: 0; }
QWidget#socConsole QTabBar::tab {
    font-size: 11px; color: #54637a; padding: 5px 10px; background: #f4f6fa;
}
QWidget#socConsole QTabBar::tab:selected { color: #2f6bff; background: #e3edff; }
QWidget#socConsole QTableWidget, QWidget#socConsole QHeaderView::section {
    font-size: 11px; background: white; color: #54637a; border: 0;
    font-family: "DejaVu Sans Mono", "Consolas", monospace;
}
QWidget#socConsole QPlainTextEdit {
    font-family: "Noto Sans Mono CJK SC", "Consolas", monospace;
    font-size: 11px; border: 0; padding: 0; min-height: 0;
}
"""


def label(text='', role=None):
    result = QLabel(text)
    if role:
        result.setProperty('role', role)
    result.setWordWrap(True)
    return result


def card(title):
    frame = QFrame()
    frame.setObjectName('card')
    box = QVBoxLayout(frame)
    box.setContentsMargins(12, 10, 12, 10)
    box.setSpacing(8)
    box.addWidget(label(title, 'title'))
    return frame, box


def form():
    box = QFormLayout()
    box.setLabelAlignment(Qt.AlignRight | Qt.AlignVCenter)
    box.setFormAlignment(Qt.AlignLeft | Qt.AlignTop)
    box.setFieldGrowthPolicy(QFormLayout.AllNonFixedFieldsGrow)
    box.setHorizontalSpacing(8)
    box.setVerticalSpacing(6)
    return box


def scroll(widget, width):
    area = QScrollArea()
    area.setFrameShape(QFrame.NoFrame)
    area.setWidgetResizable(True)
    area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
    area.setFixedWidth(width)
    area.setWidget(widget)
    return area


class SocConsole(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.setObjectName('socConsole')
        self.setStyleSheet(STYLE)
        self.engine = engine
        self.board = engine.board
        self.toast = toast
        self.last_seq = 0
        self.last_display = None
        self.generation = -1
        self.loaded_image = None
        self.comparing = False
        self.comparison = None
        self.reported_comparison = None
        self.static_image = QImage()
        self.paused = False
        self.replay = []
        self.replay_time = 0
        self.last_tick = time.monotonic()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        self._top(layout)
        main = QSplitter(Qt.Vertical)
        main.setChildrenCollapsible(False)
        workspace = QWidget()
        row = QHBoxLayout(workspace)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)
        left = QWidget()
        left_box = QVBoxLayout(left)
        left_box.setContentsMargins(0, 0, 0, 0)
        left_box.setSpacing(8)
        self.program = ProgramPanel(engine, toast)
        self.program.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Maximum)
        self.program.findChild(QLabel, 'cardTitle').setProperty('role', 'title')
        left_box.addWidget(self.program)
        self._transfers(left_box)
        left_box.addStretch()
        self.left_scroll = scroll(left, 282)
        row.addWidget(self.left_scroll)
        self._canvas(row)
        right = QWidget()
        right_box = QVBoxLayout(right)
        right_box.setContentsMargins(0, 0, 0, 0)
        right_box.setSpacing(8)
        self._controls(right_box)
        right_box.addStretch()
        row.addWidget(scroll(right, 264))
        main.addWidget(workspace)
        lower = QWidget()
        lower_box = QHBoxLayout(lower)
        lower_box.setContentsMargins(0, 0, 0, 0)
        lower_box.setSpacing(8)
        self._monitor(lower_box)
        self._log(lower_box)
        main.addWidget(lower)
        main.setStretchFactor(0, 3)
        main.setStretchFactor(1, 2)
        main.setSizes([460, 224])
        layout.addWidget(main, 1)
        self._project()

    def button(self, text, callback, primary=False):
        result = QPushButton(text)
        if primary:
            result.setObjectName('primary')
        result.clicked.connect(callback)
        return result

    def run(self, action):
        try:
            return action()
        except (OSError, ValueError, RuntimeError, KeyError, struct.error) as exc:
            self.board.fail(str(exc))
            self.toast.show_message(str(exc), error=True)
            self.message.setText(str(exc))

    def _top(self, layout):
        frame, box = card('SoC 中控台')
        heading = box.takeAt(0).widget()
        row = QHBoxLayout()
        row.setSpacing(10)
        row.addWidget(heading)
        row.addWidget(label('工程'))
        self.project = QComboBox()
        self.project.addItems(PROJECTS)
        self.project.currentTextChanged.connect(self._project)
        row.addWidget(self.project)
        self.phase = label('阶段 · 未连接')
        row.addWidget(self.phase)
        row.addStretch()
        row.addWidget(label('板子 IP'))
        self.ip = QLineEdit('192.168.1.10')
        self.ip.setFixedWidth(130)
        row.addWidget(self.ip)
        self.establish = self.button('建立网口连接', self._network, True)
        row.addWidget(self.establish)
        self.stop = self.button('停止监听', lambda: self.run(self.engine.ethernet.stop_receive))
        row.addWidget(self.stop)
        box.addLayout(row)
        steps = QHBoxLayout()
        steps.setSpacing(8)
        self.step_labels = []
        for title in ('01 · 监听 UDP 6000', '02 · WIN3 已发送',
                      '03 · status 对端一致', '04 · 视频 / EDTM 数据'):
            value = label(title + '\n未完成 · —', 'note')
            value.setMinimumHeight(36)
            value.setStyleSheet('background:#f4f6fa;border-radius:6px;padding:5px 8px;')
            self.step_labels.append(value)
            steps.addWidget(value, 1)
        box.addLayout(steps)
        layout.addWidget(frame)

    def _transfers(self, layout):
        self.image_card, box = card('图片发送 · WIN0 / WIN1')
        self.image_path = QLineEdit()
        self.image_path.setPlaceholderText('选择测试图片')
        box.addWidget(self.image_path)
        box.addWidget(self.button('选择图片并预览', self._choose_image))
        self.window = QComboBox()
        self.window.addItems(['WIN0', 'WIN1'])
        fields = form()
        fields.addRow('目标窗口', self.window)
        box.addLayout(fields)
        self.send_image = self.button('转换并发送图像', self._send_image)
        box.addWidget(self.send_image)
        self.image_note = label('', 'note')
        box.insertWidget(1, self.image_note)
        layout.addWidget(self.image_card)
        self.model_card, box = card('模型发送 · WIN2')
        self.model_path = QLineEdit()
        self.model_path.setPlaceholderText('compile_yolo.py 输出目录')
        box.addWidget(self.model_path)
        box.addWidget(self.button('选择模型目录', self._choose_model))
        self.send_model = self.button('发送描述符与模型', self._send_model)
        box.addWidget(self.send_model)
        self.model_note = label('', 'note')
        box.insertWidget(1, self.model_note)
        layout.addWidget(self.model_card)
        frame, box = card('传输状态')
        self.transfer = label('尚未发送', 'note')
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.model_result = label('WIN2_BYTES · —', 'note')
        box.addWidget(self.progress)
        box.addWidget(self.transfer)
        box.addWidget(self.model_result)
        layout.addWidget(frame)

    def _canvas(self, row):
        frame, box = card('统一显示区')
        frame.setMinimumWidth(160)
        frame.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Expanding)
        self.display = QComboBox()
        self.display.addItems(['视频', '静态图片', '检测叠加'])
        self.display.currentIndexChanged.connect(self._display)
        title = box.takeAt(0).widget()
        header = QHBoxLayout()
        header.addWidget(title, 1)
        header.addWidget(self.display)
        box.addLayout(header)
        self.view = DetectionView()
        self.view.setMinimumSize(100, 100)
        self.view.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Expanding)
        box.addWidget(self.view, 1)
        self.caption = label('来源 · 板端视频\n等待 EDVF 视频帧', 'note')
        self.caption.setMinimumHeight(34)
        box.addWidget(self.caption)
        self.video_stats = label('完整帧 0 · 缺包丢帧 0 · 网口跳帧 0', 'note')
        box.addWidget(self.video_stats)
        row.addWidget(frame, 1)

    def _controls(self, layout):
        self.scene_card, box = card('场景与流水线')
        fields = form()
        self.scene = QComboBox()
        self.scene.addItems(['S1 · 目标检测', 'S2 · 图像处理'])
        self.scene.setCurrentIndex(1)
        self.pix = QComboBox()
        self.pix.addItems(['旁路', '亮度 / 对比度', 'Gamma', '高斯', 'Sobel'])
        self.geo = QComboBox()
        self.geo.addItems(['关闭', '180° 旋转', '居中放大 2 倍'])
        for name, widget in [('场景', self.scene), ('PIX', self.pix), ('GEO', self.geo)]:
            fields.addRow(name, widget)
        box.addLayout(fields)
        self.apply_scene = self.button('下发场景与 PIX / GEO', self._apply_scene)
        box.addWidget(self.apply_scene)
        self.scene_note = label('', 'note')
        box.addWidget(self.scene_note)
        layout.addWidget(self.scene_card)
        self.output_card, box = card('输出与采样')
        fields = form()
        self.output = QComboBox()
        self.output.addItems(['HDMI', 'ETH', 'HDMI + ETH'])
        self.fps = QSpinBox()
        self.fps.setRange(1, 60)
        self.fps.setValue(30)
        self.fps.setSuffix(' fps')
        self.rate = QSpinBox()
        self.rate.setRange(10, 1000)
        self.rate.setValue(100)
        self.rate.setSuffix(' Hz')
        for name, widget in [('输出', self.output), ('视频帧率', self.fps), ('采样率', self.rate)]:
            fields.addRow(name, widget)
        box.addLayout(fields)
        self.apply_output = self.button('下发输出与采样', self._apply_output)
        box.addWidget(self.apply_output)
        self.output_note = label('', 'note')
        box.addWidget(self.output_note)
        layout.addWidget(self.output_card)
        frame, box = card('板端 status 摘要')
        box.addWidget(self.button('查询 status', lambda: self.run(
            lambda: self.engine.send('status', 'cr'))))
        fields = form()
        self.summary = {}
        for key, title in [('Scene', '场景'), ('PIX mode', 'PIX'), ('GEO mode', 'GEO'),
                           ('Output mode', '输出'), ('Requested video fps', 'fps'),
                           ('Monitor Hz', '采样 Hz')]:
            value = label('—', 'number')
            value.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            fields.addRow(title, value)
            self.summary[key] = value
        box.addLayout(fields)
        self.peer = label('Peer · —', 'note')
        box.addWidget(self.peer)
        self.switch = label('Switch · —', 'note')
        box.addWidget(self.switch)
        self.message = label('等待串口启动行', 'note')
        box.addWidget(self.message)
        layout.addWidget(frame)
        self.check_card, box = card('YOLO 图像检查')
        self.capture_status = label('等待 CH2 / OUTPUT / EDDT 回传', 'note')
        box.addWidget(self.capture_status)
        self.quant = QLineEdit(str(Path(__file__).resolve().parents[3] /
                                   'build/npu/quantized/quantization.json'))
        box.addWidget(self.quant)
        box.addWidget(self.button('选择量化 JSON', self._choose_quant))
        self.compare = self.button('运行参考模型并比对', self._compare)
        box.addWidget(self.compare)
        self.comparison_result = label('选择原图、模型与量化参数', 'note')
        box.addWidget(self.comparison_result)
        self.check_note = label('', 'note')
        box.addWidget(self.check_note)
        layout.addWidget(self.check_card)

    def _monitor(self, row):
        self.monitor_card, box = card('DDR 监控')
        box.setSpacing(4)
        header = QHBoxLayout()
        header.addWidget(box.takeAt(0).widget())
        self.chart_mode = QComboBox()
        self.chart_mode.addItems(['带宽 GB/s', '利用率 %', '读延迟'])
        header.addWidget(self.chart_mode)
        self.monitor_summary = label('利用率 — · 丢失 0', 'number')
        header.addStretch()
        self.mode = QComboBox()
        self.mode.addItems(['只看读', '只看写', '读写合计'])
        self.mode.setCurrentIndex(2)
        header.addWidget(self.mode)
        self.pause_button = self.button('暂停', self._pause)
        header.addWidget(self.pause_button)
        self.monitor_buttons = [self.pause_button]
        for title, action in [('CSV 导出', self._export), ('回放', self._open),
                              ('清空', self._clear)]:
            button = self.button(title, action)
            header.addWidget(button)
            self.monitor_buttons.append(button)
        box.addLayout(header)
        content = QHBoxLayout()
        charts = QStackedWidget()
        self.chart_mode.currentIndexChanged.connect(charts.setCurrentIndex)
        self.bandwidth = Timeline()
        self.utilization = Timeline(True)
        self.histogram = Histogram()
        for title, widget in [('带宽 GB/s', self.bandwidth), ('利用率 %', self.utilization),
                              ('读延迟', self.histogram)]:
            widget.setMinimumHeight(90)
            charts.addWidget(widget)
        content.addWidget(charts, 1)
        self.table = QTableWidget(7, 4)
        self.table.setMinimumWidth(272)
        self.table.setMaximumWidth(360)
        self.table.setHorizontalHeaderLabels(['端口', '均等候', '最长', '紧急'])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.verticalHeader().hide()
        self.table.verticalHeader().setDefaultSectionSize(19)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setMinimumHeight(120)
        for index, name in enumerate(['DISP', 'VIN', 'CPU', 'NPU', 'RND', 'GEO', 'ETH']):
            for column, value in enumerate((name, '—', '—', '0')):
                item = QTableWidgetItem(value)
                item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                self.table.setItem(index, column, item)
        content.addWidget(self.table)
        box.addLayout(content, 1)
        legend = QHBoxLayout()
        for name, color in zip(['DISP', 'VIN', 'CPU', 'NPU', 'RND', 'GEO', 'ETH'], COLORS):
            text = label('● ' + name, 'note')
            text.setStyleSheet(f'color:{color};')
            legend.addWidget(text)
        box.addLayout(legend)
        metrics = QHBoxLayout()
        metrics.addWidget(self.monitor_summary)
        self.realtime = label('DISP 读空 0 · VIN CH0 / CH2 溢出 0 / 0', 'note')
        metrics.addWidget(self.realtime, 1)
        box.addLayout(metrics)
        self.monitor_note = label('60 s · 读深色 / 写浅色 · 等候单位 clk_mem 周期', 'note')
        box.addWidget(self.monitor_note)
        row.addWidget(self.monitor_card, 1)

    def _log(self, row):
        frame, box = card('会话日志')
        frame.setFixedWidth(300)
        header = QHBoxLayout()
        header.addWidget(label('UART · 传输 · 回传', 'note'), 1)
        header.addWidget(self.button('保存', lambda: self.run(self.engine.save_log)))
        box.addLayout(header)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(500)
        self.log.setLineWrapMode(QPlainTextEdit.WidgetWidth)
        box.addWidget(self.log, 1)
        row.addWidget(frame)

    def _project(self, *_):
        project = self.project.currentText()
        self.board.select_project(project)
        caps = PROJECTS[project]
        reason = caps['reason']
        for widget in (self.image_card, self.model_card, self.check_card):
            for control in widget.findChildren(QWidget):
                if isinstance(control, (QPushButton, QLineEdit, QComboBox)):
                    control.setEnabled(caps['detection'])
        for note in (self.image_note, self.model_note, self.check_note):
            note.setText(reason if not caps['detection'] else
                         '1280 × 720 RGB565' if note is self.image_note else
                         'EDNM · 板端结果见日志' if note is self.model_note else
                         '逐字节比较输入与输出；按序比较检测框')
        for widget in (self.scene, self.pix, self.geo, self.apply_scene):
            widget.setEnabled(caps['processing'])
        self.display.setEnabled(caps['network'])
        self.scene.model().item(0).setEnabled(caps['detection'])
        if not caps['detection']:
            self.scene.setCurrentIndex(1)
        self.display.model().item(2).setEnabled(caps['detection'])
        if not caps['detection'] and self.display.currentIndex() == 2:
            self.display.setCurrentIndex(0)
        self.scene_note.setText(reason if not caps['processing'] else
                                'B3V 没有 NPU；仅 S2' if not caps['detection'] else
                                'PIX / GEO 仅在 S2 生效')
        for widget in (self.output, self.fps, self.rate, self.apply_output,
                       self.establish, self.ip, self.mode, self.chart_mode, self.pause_button):
            widget.setEnabled(caps['network'])
        self.output_note.setText('UDP 5000 → PC 6000' if caps['network'] else reason)
        self.monitor_note.setText('60 s · 读深色 / 写浅色 · 等候单位 clk_mem 周期'
                                  if caps['network'] else reason)
        for button in self.monitor_buttons:
            button.setEnabled(caps['network'])
        self.histogram.setEnabled(caps['network'])
        self.view.setEnabled(caps['network'])
        self.bandwidth.setEnabled(caps['network'])
        self.utilization.setEnabled(caps['network'])
        self.table.setEnabled(caps['network'])

    def _network(self):
        self.run(lambda: self.board.establish_network(self.ip.text(), 5000))
        self.refresh()

    def _choose_model(self):
        path = QFileDialog.getExistingDirectory(self, '选择模型编译输出目录')
        if path:
            self.model_path.setText(path)

    def _choose_quant(self):
        path, _ = QFileDialog.getOpenFileName(self, '后处理量化参数', filter='JSON (*.json)')
        if path:
            self.quant.setText(path)

    def _choose_image(self):
        path, _ = QFileDialog.getOpenFileName(self, '选择测试图片')
        if path:
            self.image_path.setText(path)
            self.run(self._load_image)
            self.display.setCurrentIndex(1)

    def _load_image(self):
        from PySide6.QtGui import QImageReader
        reader = QImageReader(self.image_path.text())
        image = reader.read()
        if image.isNull():
            raise ValueError(f'无法读取图片：{reader.errorString()}')
        self.static_image = image.scaled(1280, 720, Qt.IgnoreAspectRatio,
                                         Qt.SmoothTransformation)
        self.loaded_image = self.image_path.text()
        self.last_display = None
        self._display()

    def _send_image(self):
        def send():
            self._load_image()
            if not self.engine.ethernet.status()['rx']['active']:
                self.engine.ethernet.start_receive(6000, mode='console')
            self.engine.yolo.send_image(self.image_path.text(), self.ip.text(), 5000,
                                        6000, self.window.currentIndex())
            self.display.setCurrentIndex(2)
            self.comparison = None
            self.comparison_result.setText('等待本次回传')
        self.run(send)

    def _send_model(self):
        self.run(lambda: self.engine.yolo.send_model(
            self.model_path.text(), self.ip.text(), 5000, 6000))
        self.model_result.setText(f'WIN2_BYTES 期望 {self.engine.yolo.image_bytes:,} B')

    def _apply_scene(self):
        def send():
            self.engine.scenes.send(['s1', 's2'][self.scene.currentIndex()])
            if self.scene.currentIndex() == 1:
                self.engine.scenes.send(['pix_bypass', 'pix_brightness', 'pix_gamma',
                                         'pix_gaussian', 'pix_sobel'][self.pix.currentIndex()])
                self.engine.send(['geo off', 'geo rotate', 'geo scale'][
                    self.geo.currentIndex()], 'cr')
        self.run(send)

    def _apply_output(self):
        def send():
            self.engine.scenes.send(['output_hdmi', 'output_eth', 'output_both'][
                self.output.currentIndex()])
            self.engine.scenes.send('video_fps', self.fps.value())
            self.engine.scenes.send('sample_rate', self.rate.value())
            self.engine.send('status', 'cr')
        self.run(send)

    def _compare(self):
        image, model, quant = self.image_path.text(), self.model_path.text(), self.quant.text()
        self.comparing = True
        self.comparison = None
        self.comparison_result.setText('参考模型运行中…')

        def run():
            try:
                parameters = json.loads(Path(quant).read_text(encoding='utf-8'))
                self.comparison = self.engine.yolo.compare(image, model, parameters)
            except (OSError, ValueError, RuntimeError, ImportError, KeyError, struct.error) as exc:
                self.comparison = str(exc)
            finally:
                self.comparing = False
        threading.Thread(target=run, name='yolo-reference', daemon=True).start()

    def _display(self, *_):
        state = self.engine.video.snapshot()
        frame, detections = state['frame'], state['detections']
        _, capture = self.engine.yolo.snapshot()
        mode = self.display.currentIndex()
        returned = self.engine.yolo.return_view
        if mode == 1 or (mode == 2 and returned):
            image = self.static_image
            boxes = capture[2].boxes if mode == 2 and capture is not None else ()
            source = ('静态原图' if mode == 1 else
                      '回传图像检查' if capture is not None else '等待图像检查回传')
            number = capture[2].frame_id if mode == 2 and capture is not None else '—'
            key = (mode, self.static_image.cacheKey(), self.generation)
            caption = f'来源 · {source} · FRAME {number}\n1280 × 720 · {len(boxes)} 个检测框'
        elif frame is not None:
            boxes = detections.boxes if mode == 2 and detections is not None else ()
            key = (mode, frame.frame_id, boxes, round(state["fps"], 1))
            if key == self.last_display:
                return
            image = QImage(frame.pixels, frame.width, frame.height, frame.stride,
                           QImage.Format_RGB16).copy()
            caption = (f'来源 · 板端视频 · FRAME {frame.frame_id} · {state["fps"]:.1f} fps\n'
                       f'{frame.width} × {frame.height} · S{frame.scene} · {len(boxes)} 个检测框')
        else:
            image, boxes, key = QImage(), (), None
            caption = '来源 · 板端视频\n等待 EDVF 视频帧'
        if not PROJECTS[self.project.currentText()]['network']:
            image, boxes = QImage(), ()
        self.view.set_image(image, boxes)
        if not PROJECTS[self.project.currentText()]['network']:
            caption = PROJECTS[self.project.currentText()]['reason']
        self.caption.setText(caption)
        self.last_display = key

    def _pause(self):
        self.paused = not self.paused
        self.pause_button.setText('继续' if self.paused else '暂停')

    def _clear(self):
        self.replay = []
        self.engine.telemetry.clear()
        self._refresh_monitor(force=True)

    def _export(self):
        path, _ = QFileDialog.getSaveFileName(self, '导出监控数据', 'telemetry.csv', 'CSV (*.csv)')
        if path:
            self.run(lambda: self.engine.telemetry.export_csv(path))

    def _open(self):
        path, _ = QFileDialog.getOpenFileName(self, '回放监控数据', filter='CSV (*.csv)')
        if not path:
            return
        def load():
            self.engine.ethernet.stop_receive()
            self.engine.telemetry.load_csv(path)
            self.replay = list(self.engine.telemetry.records)
            self.engine.telemetry.clear()
            self.replay_time = (self.replay[0]['mtime'] / self.replay[0]['clk_sys_hz']
                                if self.replay else 0)
            self.paused = False
            self.last_tick = time.monotonic()
            self.monitor_note.setText('CSV 回放 · ' + Path(path).name)
        self.run(load)

    def _refresh_monitor(self, force=False):
        now = time.monotonic()
        elapsed, self.last_tick = now - self.last_tick, now
        if self.paused and not force:
            return
        if self.replay:
            self.replay_time += elapsed
            while (self.replay and self.replay[0]['mtime'] / self.replay[0]['clk_sys_hz']
                   <= self.replay_time):
                self.engine.telemetry.ingest(encode(self.replay.pop(0)))
        history, state = self.engine.telemetry.snapshot()
        self.bandwidth.rows = self.utilization.rows = history
        self.bandwidth.mode = self.mode.currentIndex()
        self.histogram.record = state['histogram']
        for widget in (self.bandwidth, self.utilization, self.histogram):
            widget.update()
        row = state['latest']
        if row is None:
            for index in range(7):
                for column in range(1, 4):
                    self.table.item(index, column).setText('0' if column == 3 else '—')
                    self.table.item(index, column).setForeground(QColor('#54637a'))
            self.realtime.setText('DISP 读空 0 · VIN CH0 / CH2 溢出 0 / 0')
            self.realtime.setStyleSheet('color:#7a8b9d;')
        self.monitor_summary.setText((f"利用率 {row['utilization']:.1%}" if row else '利用率 —') +
                                     f" · 丢失 {state['lost']}")
        if row:
            for index, port in enumerate(row['ports']):
                for column, text in enumerate((f"{port['wait_avg']:.1f}",
                                                str(port['wait_max']), str(port['urg_cnt'])), 1):
                    self.table.item(index, column).setText(text)
                    self.table.item(index, column).setForeground(QColor(
                        '#d24b5c' if column == 3 and port['urg_cnt'] else '#54637a'))
            values = (row['disp_underflow'], row['vin_ch0_overflow'], row['vin_ch2_overflow'])
            self.realtime.setText(f'DISP 读空 {values[0]} · VIN CH0 / CH2 溢出 '
                                  f'{values[1]} / {values[2]}')
            self.realtime.setStyleSheet(f'color:{"#d24b5c" if any(values) else "#7a8b9d"};')
            if PROJECTS[self.project.currentText()]['detection']:
                recent = [sample for sample in history
                          if sample['time_s'] > row['time_s'] - 1]
                detection_fps = sum(sample['npu_completed'] for sample in recent) * 125e6 / sum(
                    sample['window_cyc'] for sample in recent)
                self.monitor_note.setText(f"NPU {row['npu_ms']:.1f} ms · 后处理 "
                                          f"{row['post_ms']:.1f} ms · 框 {row['boxes']} · "
                                          f"{detection_fps:.1f} fps · 读深 / 写浅")

    def refresh(self):
        state = self.board.status()
        if self.project.currentText() != state['project']:
            self.project.setCurrentText(state['project'])
        self.phase.setText('阶段 · ' + {'disconnected': '未连接', 'bios': 'BIOS',
                                      'application': '应用'}[state['phase']])
        for index, (key, title) in enumerate(zip(('listen', 'win3', 'peer', 'data'),
                ('01 · 监听 UDP 6000', '02 · WIN3 已发送', '03 · status 对端一致',
                 '04 · 视频 / EDTM 数据'))):
            step = state['network'][key]
            stamp = fmt_ts(step['time'])[:8] if step['time'] else '—'
            text = f'{title}\n{"已完成" if step["done"] else "未完成"} · {stamp}'
            if key == 'data':
                text = (f"{title}\n视频 {state['counts']['video']} · "
                        f"EDTM {state['counts']['telemetry']} · {stamp}")
            self.step_labels[index].setText(text)
            self.step_labels[index].setStyleSheet(
                'border-radius:6px;padding:5px 8px;' +
                ('background:#eaf7f0;color:#218255;' if step['done'] else
                 'background:#f4f6fa;color:#7a8b9d;'))
        self.stop.setEnabled(state['network']['listen']['done'])
        for key, value in self.summary.items():
            value.setText(state['summary'].get(key, '—'))
        self.peer.setText(f"Peer · {state['peer'][0] or '—'} : {state['peer'][1] or '—'}")
        self.switch.setText('Switch · ' + state['summary'].get('Switch', '—'))
        self.message.setText(state['error'] or
                             ('应用运行中' if state['phase'] == 'application' else
                              'BIOS 菜单可直接开始烧录' if state['phase'] == 'bios' else
                              '连接串口后等待启动行'))
        self.message.setStyleSheet(f'color:{"#d24b5c" if state["error"] else "#7a8b9d"};')
        self.program.refresh()
        tx = self.engine.ethernet.status()['tx']
        self.progress.setValue(int(tx['sent'] / tx['total'] * 100) if tx['total'] else 0)
        self.transfer.setText(f"{tx['sent']:,} / {tx['total']:,} B\n" +
                               (tx['error'] or ('发送中' if tx['active'] else '就绪')))
        caps = PROJECTS[self.project.currentText()]
        self.send_image.setEnabled(caps['detection'] and not tx['active'])
        self.send_model.setEnabled(caps['detection'] and not tx['active'])
        source_image = self.engine.yolo.source_image
        if source_image is not None and source_image != self.loaded_image:
            self.image_path.setText(source_image)
            self.run(self._load_image)
        generation, capture = self.engine.yolo.snapshot()
        if capture is not None and generation != self.generation:
            self.generation = generation
            self.last_display = None
            self.board.log(f'YOLO 回传完整：FRAME {capture[2].frame_id} · '
                           f'{len(capture[2].boxes)} 个框')
            self.capture_status.setText(f'FRAME {capture[2].frame_id} · '
                                        f'{len(capture[2].boxes)} 个检测框；三块回传完整')
        self.compare.setEnabled(caps['detection'] and not self.comparing)
        if self.comparison is not None and self.comparison is not self.reported_comparison:
            self.reported_comparison = self.comparison
            if isinstance(self.comparison, str):
                self.comparison_result.setText('参考比对失败：' + self.comparison)
                self.board.fail(self.comparison_result.text())
            else:
                result = self.comparison
                first = result['output']['first']
                first_text = '无' if first is None else f'{first} / 0x{first:x}'
                self.comparison_result.setText(
                    f"CH2 差异 {result['input']['count']} B\n"
                    f"OUTPUT 差异 {result['output']['count']} B\n"
                    f"首个差异 {first_text}\n"
                    f"检测差异 {result['detections']['count']} 个框\n"
                    f"参考 {result['detections']['expected']} / "
                    f"板端 {result['detections']['actual']}")
                self.board.log(self.comparison_result.text())
        self._display()
        video = self.engine.video.snapshot()
        self.video_stats.setText(f"完整帧 {video['received']} · 缺包丢帧 {video['dropped']} · "
                                 f"网口跳帧 {self.engine.telemetry.status()['video_skipped']}")
        self._refresh_monitor()
        entries, _ = self.engine.get_entries(self.last_seq, 500)
        for entry in entries:
            self.log.appendPlainText(f"[{fmt_ts(entry['ts'])[:8]}] "
                                      f"{entry['dir'].upper()} {entry['text']}")
            self.last_seq = entry['seq']
