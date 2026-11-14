"""soc_console.py — SoC console design 4.1–4.5; host Qt thread.

One shared canvas and UDP session serve device, processing and detection pages.
Scrollable controls keep complete groups readable at both desktop sizes.
"""

import json
from pathlib import Path
import struct
import threading
import time

from PySide6.QtCore import QEvent, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QImage, QIntValidator, QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QCheckBox, QSpinBox, QComboBox, QFileDialog, QFormLayout, QFrame, QGridLayout, QHBoxLayout,
    QHeaderView, QLabel, QLineEdit, QPlainTextEdit, QProgressBar, QPushButton,
    QSizePolicy, QStackedLayout, QStackedWidget, QTableWidget, QTabWidget, QScrollArea,
    QTableWidgetItem, QVBoxLayout, QWidget,
)
from core.engine import fmt_ts
from core.showcase import STATUS
from gui.processing import ProcessingPanel
from core.telemetry import encode
from core.video import FrameRate
from gui.program import ProgramPanel
from gui.telemetry import Histogram, Timeline
from gui.video import DetectionView

STYLE = """
QWidget#socConsole { background: #f3f5f8; }
QWidget#socConsole, QWidget#socConsole QLabel { font-size: 12px; color: #33404d; }
QWidget#socConsole QLabel[role="title"] {
    font-size: 14px; font-weight: 700; color: #2f6bff; letter-spacing: 0px;
}
QWidget#socConsole QLabel[role="note"] { font-size: 11px; color: #7a8b9d; }
QWidget#socConsole QLabel[role="number"],
QWidget#socConsole QLineEdit[role="number"] {
    font-family: "DejaVu Sans Mono", "Consolas", monospace; font-size: 12px;
}
QWidget#socConsole QCheckBox { spacing: 7px; min-height: 22px; }
QWidget#socConsole QCheckBox::indicator {
    width: 14px; height: 14px; border: 1px solid #8b98a9;
    border-radius: 4px; background: white;
}
QWidget#socConsole QCheckBox::indicator:checked { background: #2f6bff; border-color: #2f6bff; }
QWidget#socConsole QGroupBox {
    font-size: 12px; font-weight: 600; padding-top: 14px; margin-top: 8px;
}
QWidget#socConsole QGroupBox::title { subcontrol-origin: margin; left: 5px; }
QWidget#socConsole QPushButton { font-size: 12px; padding: 3px 8px; }
QWidget#socConsole QLineEdit, QWidget#socConsole QComboBox,
QWidget#socConsole QSpinBox {
    font-size: 12px; min-height: 20px; padding: 2px 6px;
}
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
    box.setContentsMargins(8, 6, 8, 6)
    box.setSpacing(4)
    heading = label(title, 'title')
    heading.setWordWrap(False)
    box.addWidget(heading)
    return frame, box


def form():
    box = QFormLayout()
    box.setLabelAlignment(Qt.AlignRight | Qt.AlignVCenter)
    box.setFormAlignment(Qt.AlignLeft | Qt.AlignTop)
    box.setFieldGrowthPolicy(QFormLayout.AllNonFixedFieldsGrow)
    box.setHorizontalSpacing(8)
    box.setVerticalSpacing(6)
    return box


class SocConsole(QWidget):
    network_changed = Signal()
    def __init__(self, engine, toast):
        super().__init__()
        self.setObjectName('socConsole')
        self.setStyleSheet(STYLE)
        self.engine = engine
        self.board = engine.board
        self.toast = toast
        self.state_generation = -1
        self.last_seq = 0
        self.last_display = None
        self.display_rate = FrameRate()
        self.displayed_frame = None
        self.generation = -1
        self.loaded_image = None
        self.last_source_image = None
        self.comparing = False
        self.comparison = None
        self.reported_comparison = None
        self.static_image = QImage()
        self.paused = False
        self.replay = []
        self.replay_time = 0
        self.last_tick = time.monotonic()
        self.expanded_panel = None
        self.panel_buttons = {}
        self.panel_titles = {}
        self.panel_stack = QStackedLayout(self)
        self.panel_stack.setContentsMargins(0, 0, 0, 0)
        self.normal = QWidget()
        self.expanded = QWidget()
        self.expanded_layout = QVBoxLayout(self.expanded)
        self.expanded_layout.setContentsMargins(0, 0, 0, 0)
        self.panel_stack.addWidget(self.normal)
        self.panel_stack.addWidget(self.expanded)
        self.restore_shortcut = QShortcut(QKeySequence(Qt.Key_Escape), self)
        self.restore_shortcut.setContext(Qt.WindowShortcut)
        self.restore_shortcut.activated.connect(self.restore_panel)
        layout = QVBoxLayout(self.normal)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        self._top(layout)
        self.workspace = QWidget()
        row = QHBoxLayout(self.workspace)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)
        self.pages = QTabWidget()
        self.pages.setFixedWidth(430)
        row.addWidget(self.pages)
        self.device_box = self.page('设备与输出')
        self.program = ProgramPanel(engine, toast)
        self.device_box.addWidget(self.program)
        processing_box = self.page('图像处理')
        self.processing = ProcessingPanel(engine.processing, self.run)
        processing_box.addWidget(self.processing)
        detection_box = self.page('目标检测')
        self._transfers(detection_box)
        self._controls(self.device_box)
        self.device_box.removeWidget(self.check_card)
        detection_box.addWidget(self.check_card)
        self._session_controls(self.device_box)
        self._detector_controls(detection_box)
        for box in (self.device_box, processing_box, detection_box):
            box.addStretch()
        self._canvas(row)
        layout.addWidget(self.workspace, 1)
        self.lower = QWidget()
        self.lower.setFixedHeight(278)
        lower_box = QHBoxLayout(self.lower)
        lower_box.setContentsMargins(0, 0, 0, 0)
        lower_box.setSpacing(8)
        self._monitor(lower_box)
        self._log(lower_box)
        layout.addWidget(self.lower)
        self.image_note.setText('1280 × 720 RGB565 · 自动缩放')
        self.model_note.setText('选择模型编译目录，然后发送')
        self.check_note.setText('输入 / 输出逐字节比对；检测框按序比对')
        self.output_note.setText('UDP 5000 → PC 6000')
        # Video needs its own cadence; the shared status panel refreshes at 2 Hz.
        self.video_timer = QTimer(self)
        self.video_timer.setTimerType(Qt.PreciseTimer)
        self.video_timer.timeout.connect(self._video_tick)
        self.video_timer.start(16)
        self.network_changed.connect(self.refresh)
        self.board.listeners.append(self.network_changed.emit)

    def _session_controls(self, layout):
        frame, box = card('板端应用')
        self.app_choice = QComboBox()
        self.app_choice.addItems(['无', '实时识别', '图片识别', '图像处理', '图形测试',
                                 '游戏', '芯片性能测试'])
        box.addWidget(self.app_choice)
        self.app_arg = QLineEdit('0')
        self.app_arg.setValidator(QIntValidator(0, 65535, self))
        self.app_arg.setToolTip('游戏序号')
        box.addWidget(label('游戏序号', 'note'))
        box.addWidget(self.app_arg)
        for action, title in enumerate(['打开', '暂停', '继续', '重试']):
            box.addWidget(self.button(title, lambda checked=False, a=action: self.run(
                lambda: self.engine.ethernet.showcase.app(
                    self.app_choice.currentIndex(), a,
                    int(self.app_arg.text()) if self.app_choice.currentIndex() == 5 else 0))))
        layout.addWidget(frame)

    def _detector_controls(self, layout):
        frame, box = card('检测设置')
        self.detect_threshold = QSpinBox()
        self.detect_threshold.setRange(25, 90)
        self.detect_threshold.lineEdit().setStyleSheet('border:0; padding:0; min-height:0;')
        self.detect_threshold.setSuffix(' %')
        box.addWidget(self.detect_threshold)
        self.class_checks = []
        from core.labels import COCO_NAMES
        for name in COCO_NAMES:
            check = QCheckBox(name)
            self.class_checks.append(check)
            box.addWidget(check)
        self.detect_threshold.valueChanged.connect(self.send_detection)
        for check in self.class_checks:
            check.toggled.connect(self.send_detection)
        layout.addWidget(frame)
        self.last_detection = None

    def sync_detection(self, state, force=False):
        if force:
            self.app_choice.setCurrentIndex(state['app'])
        current = (state['threshold'], tuple(state['classes']))
        if not force and current == self.last_detection:
            return
        self.last_detection = current
        self.detect_threshold.blockSignals(True)
        self.detect_threshold.setValue(state['threshold'])
        self.detect_threshold.blockSignals(False)
        for index, check in enumerate(self.class_checks):
            check.blockSignals(True)
            check.setChecked(bool(state['classes'][index // 32] & (1 << (index % 32))))
            check.blockSignals(False)

    def send_detection(self, *_):
        from core.showcase import DETECT
        classes = [0, 0, 0]
        for index, check in enumerate(self.class_checks):
            if check.isChecked():
                classes[index // 32] |= 1 << (index % 32)
        payload = struct.pack('<B3x3I', self.detect_threshold.value(), *classes)
        self.run(lambda: self.engine.ethernet.showcase.command(DETECT, payload))

    def closeEvent(self, event):
        self.board.listeners.remove(self.network_changed.emit)
        super().closeEvent(event)

    def panel_header(self, panel, box):
        heading = box.takeAt(0).widget()
        heading.installEventFilter(self)
        self.panel_titles[heading] = panel
        header = QHBoxLayout()
        header.addWidget(heading, 1)
        button = self.button('放大', lambda: self.toggle_panel(panel))
        button.setToolTip('放大此面板；再次点击或按 Esc 复原')
        self.panel_buttons[panel] = button
        header.addWidget(button)
        box.addLayout(header)
        return header

    def eventFilter(self, watched, event):
        if (watched in self.panel_titles and event.type() == QEvent.MouseButtonDblClick
                and event.button() == Qt.LeftButton):
            self.toggle_panel(self.panel_titles[watched])
            return True
        return super().eventFilter(watched, event)

    def toggle_panel(self, panel):
        if self.expanded_panel is panel:
            self.restore_panel()
            return
        self.restore_panel()
        self.panel_origin = panel.parentWidget().layout()
        self.panel_placeholder = QWidget()
        self.panel_origin.replaceWidget(panel, self.panel_placeholder)
        self.panel_constraints = (panel.minimumSize(), panel.maximumSize())
        panel.setMinimumSize(0, 0)
        panel.setMaximumSize(16777215, 16777215)
        self.expanded_layout.addWidget(panel)
        self.expanded_panel = panel
        self.panel_buttons[panel].setText('复原')
        self.panel_stack.setCurrentWidget(self.expanded)
        panel.show()
        self.panel_buttons[panel].setFocus()

    def restore_panel(self):
        panel = self.expanded_panel
        if panel is None:
            return
        self.expanded_layout.removeWidget(panel)
        panel.setParent(self.panel_placeholder.parentWidget())
        self.panel_origin.replaceWidget(self.panel_placeholder, panel)
        self.panel_placeholder.deleteLater()
        panel.setMinimumSize(self.panel_constraints[0])
        panel.setMaximumSize(self.panel_constraints[1])
        self.panel_buttons[panel].setText('放大')
        self.expanded_panel = None
        self.panel_stack.setCurrentWidget(self.normal)
        panel.show()

    def page(self, title):
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        content = QWidget()
        box = QVBoxLayout(content)
        box.setContentsMargins(8, 8, 8, 8)
        box.setSpacing(10)
        scroll.setWidget(content)
        self.pages.addTab(scroll, title)
        return box

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
        frame, box = card('设备调试')
        heading = box.takeAt(0).widget()
        row = QHBoxLayout()
        row.setSpacing(10)
        row.addWidget(heading)
        self.phase = label('阶段 · 未连接')
        row.addWidget(self.phase)
        row.addStretch()
        row.addWidget(label('板子 IP'))
        self.ip = QLineEdit('192.168.1.10')
        self.ip.setFixedWidth(130)
        row.addWidget(self.ip)
        row.addWidget(QLabel('本机地址'))
        self.local_ip = QLineEdit(self.engine.ethernet.local_ip)
        self.local_ip.setFixedWidth(130)
        row.addWidget(self.local_ip)
        self.establish = self.button('建立网口连接', self._network, True)
        row.addWidget(self.establish)
        self.stop = self.button('停止监听', lambda: self.run(self.engine.ethernet.stop_receive))
        row.addWidget(self.stop)
        box.addLayout(row)
        steps = QHBoxLayout()
        steps.setSpacing(8)
        self.step_labels = []
        for title in ('01 · 监听 UDP 6000', '02 · 连接请求已发送',
                      '03 · 板端已连接', '04 · 视频 / EDTM 数据'):
            value = label(title + '\n未完成 · —', 'note')
            value.setMinimumHeight(36)
            value.setStyleSheet('background:#f4f6fa;border-radius:6px;padding:5px 8px;')
            self.step_labels.append(value)
            steps.addWidget(value, 1)
        box.addLayout(steps)
        layout.addWidget(frame)

    def _transfers(self, layout):
        self.image_card, box = card('图片或文件夹')
        self.image_path = QLineEdit()
        self.image_path.setPlaceholderText('选择测试图片')
        path_row = QHBoxLayout()
        path_row.addWidget(self.image_path, 1)
        path_row.addWidget(self.button('选择', self._choose_image))
        self.choose_folder = self.button('文件夹', self._choose_folder)
        path_row.addWidget(self.choose_folder)
        box.addLayout(path_row)
        send_row = QHBoxLayout()
        self.send_image = self.button('发送图像', self._send_image)
        send_row.addWidget(self.send_image)
        self.cancel_image = self.button('取消', lambda: self.run(
            self.engine.ethernet.showcase.cancel))
        send_row.addWidget(self.cancel_image)
        self.image_camera = self.button('回到摄像头检测', self._camera_detection)
        send_row.addWidget(self.image_camera)
        box.addLayout(send_row)
        navigation = QHBoxLayout()
        self.previous_image = self.button('上一张', lambda: self.run(
            lambda: self.engine.yolo.step(-1)))
        self.next_image = self.button('下一张', lambda: self.run(
            lambda: self.engine.yolo.step(1)))
        navigation.addWidget(self.previous_image)
        navigation.addWidget(self.next_image)
        box.addLayout(navigation)
        self.image_note = label('', 'note')
        self.image_note.setWordWrap(True)
        box.insertWidget(1, self.image_note)
        layout.addWidget(self.image_card)
        self.model_card, box = card('模型加载')
        self.model_path = QLineEdit()
        self.model_path.setPlaceholderText('compile_yolo.py 输出目录')
        path_row = QHBoxLayout()
        path_row.addWidget(self.model_path, 1)
        path_row.addWidget(self.button('目录', self._choose_model))
        box.addLayout(path_row)
        self.send_model = self.button('发送描述符与模型', self._send_model)
        box.addWidget(self.send_model)
        self.model_note = label('', 'note')
        self.model_note.setWordWrap(True)
        box.insertWidget(1, self.model_note)
        layout.addWidget(self.model_card)
        frame, box = card('传输状态')
        self.transfer = label('尚未发送', 'note')
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.model_result = label('模型字节数 · —', 'note')
        box.addWidget(self.progress)
        box.addWidget(self.transfer)
        box.addWidget(self.model_result)
        layout.addWidget(frame)

    def _canvas(self, row):
        frame, box = card('统一显示区')
        self.canvas_card = frame
        box.setSpacing(2)
        frame.setMinimumWidth(160)
        frame.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Expanding)
        self.display = QComboBox()
        self.display.addItems(['视频', '静态图片', '检测叠加'])
        self.display.currentIndexChanged.connect(self._display)
        header = self.panel_header(frame, box)
        header.insertWidget(1, self.display)
        self.view = DetectionView()
        self.view.setMinimumSize(100, 100)
        self.view.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Expanding)
        box.addWidget(self.view, 1)
        self.caption = label('来源 · 板端视频\n等待 EDVF 视频帧', 'note')
        self.caption.setWordWrap(True)
        box.addWidget(self.caption)
        self.video_stats = label('接收帧率 0.0 fps · 显示帧率 0.0 fps · 丢弃帧数 0 · 接收缓冲 0 MiB', 'note')
        box.addWidget(self.video_stats)
        self.video_camera = self.button('回到摄像头检测', self._camera_detection)
        box.addWidget(self.video_camera)
        row.addWidget(frame, 1)

    def _controls(self, layout):
        self.scene_card, box = card('摄像头输入')
        self.scene = QComboBox()
        self.scene.addItems(['摄像头目标检测', '摄像头图像处理'])
        self.scene.setCurrentIndex(1)
        box.addWidget(self.scene)
        self.apply_scene = self.button('切换摄像头功能', self._apply_scene)
        box.addWidget(self.apply_scene)
        layout.addWidget(self.scene_card)
        self.output_card, box = card('输出与采样')
        fields = form()
        self.output = QComboBox()
        self.output.addItems(['HDMI', 'ETH', 'HDMI + ETH'])
        self.fps = QLineEdit('30')
        self.fps.setValidator(QIntValidator(1, 60, self.fps))
        self.rate = QLineEdit('100')
        self.rate.setValidator(QIntValidator(10, 1000, self.rate))
        fields.addRow('输出', self.output)
        for name, widget, unit in [('视频帧率', self.fps, 'fps'),
                                   ('采样率', self.rate, 'Hz')]:
            widget.setAlignment(Qt.AlignRight)
            widget.setProperty('role', 'number')
            field_row = QHBoxLayout()
            field_row.addWidget(widget, 1)
            field_row.addWidget(label(unit))
            fields.addRow(name, field_row)
        box.addLayout(fields)
        self.apply_output = self.button('下发输出与采样', self._apply_output)
        box.addWidget(self.apply_output)
        self.output_note = label('', 'note')
        self.output_note.setWordWrap(False)
        box.addWidget(self.output_note)
        layout.addWidget(self.output_card)
        self.status_card, box = card('板端 status 摘要')
        self.panel_header(self.status_card, box)
        fields = QGridLayout()
        fields.setHorizontalSpacing(6)
        fields.setVerticalSpacing(3)
        self.summary = {}
        for index, (key, title) in enumerate([
                ('Scene', '场景'), ('PIX mode', 'PIX'), ('GEO mode', 'GEO'),
                ('Output mode', '输出'), ('Requested video fps', 'fps'),
                ('Monitor Hz', '采样 Hz')]):
            value = label('—', 'number')
            value.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            name = label(title)
            name.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            fields.addWidget(name, index // 2, index % 2 * 2)
            fields.addWidget(value, index // 2, index % 2 * 2 + 1)
            self.summary[key] = value
        box.addLayout(fields)
        self.peer = label('Peer · —', 'note')
        box.addWidget(self.peer)
        self.switch = label('Switch · —', 'note')
        box.addWidget(self.switch)
        self.message = label('等待串口启动行', 'note')
        box.addWidget(self.message)
        self.status_query = self.button('读取状态', lambda: self.run(
            lambda: self.engine.send('status', 'cr')))
        box.addWidget(self.status_query)
        layout.addWidget(self.status_card)
        self.check_card, box = card('YOLO 图像检查')
        self.capture_status = label('等待 CH2 / OUTPUT / EDDT 回传', 'note')
        box.addWidget(self.capture_status)
        self.quant = QLineEdit(str(Path(__file__).resolve().parents[3] /
                                   'build/npu/quantized/quantization.json'))
        quant_row = QHBoxLayout()
        quant_row.addWidget(self.quant, 1)
        quant_row.addWidget(self.button('JSON', self._choose_quant))
        box.addLayout(quant_row)
        self.compare = self.button('运行参考模型并比对', self._compare)
        box.addWidget(self.compare)
        self.comparison_result = label('选择原图、模型与量化参数', 'note')
        box.addWidget(self.comparison_result)
        self.check_note = label('', 'note')
        self.check_note.setWordWrap(True)
        box.addWidget(self.check_note)
        layout.addWidget(self.check_card)

    def _monitor(self, row):
        self.monitor_card, box = card('DDR 监控')
        box.setSpacing(4)
        self.panel_header(self.monitor_card, box)
        controls = QHBoxLayout()
        self.chart_mode = QComboBox()
        self.chart_mode.addItems(['带宽 GB/s', '利用率 %', '读延迟'])
        controls.addWidget(self.chart_mode)
        self.monitor_summary = label('利用率 — · 丢失 0', 'number')
        controls.addStretch()
        self.mode = QComboBox()
        self.mode.addItems(['只看读', '只看写', '读写合计'])
        self.mode.setCurrentIndex(2)
        controls.addWidget(self.mode)
        self.pause_button = self.button('暂停', self._pause)
        controls.addWidget(self.pause_button)
        self.monitor_buttons = [self.pause_button]
        for title, action in [('CSV 导出', self._export), ('回放', self._open),
                              ('清空', self._clear)]:
            button = self.button(title, action)
            controls.addWidget(button)
            self.monitor_buttons.append(button)
        box.addLayout(controls)
        content = QHBoxLayout()
        charts = QStackedWidget()
        self.chart_mode.currentIndexChanged.connect(charts.setCurrentIndex)
        self.bandwidth = Timeline()
        self.scale_button = self.bandwidth.scale_button()
        controls.insertWidget(1, self.scale_button)
        self.chart_mode.currentIndexChanged.connect(
            lambda index: self.scale_button.setVisible(index == 0))
        self.utilization = Timeline(True, axis=self.bandwidth.axis)
        self.histogram = Histogram()
        for title, widget in [('带宽 GB/s', self.bandwidth), ('利用率 %', self.utilization),
                              ('读延迟', self.histogram)]:
            widget.setMinimumHeight(90)
            charts.addWidget(widget)
        plot_column = QVBoxLayout()
        plot_column.setSpacing(0)
        plot_column.addWidget(charts, 1)
        content.addLayout(plot_column, 1)
        self.table = QTableWidget(7, 4)
        self.table.setFixedWidth(294)
        self.table.setHorizontalHeaderLabels(['端口', '平均等待', '最长', '紧急'])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.verticalHeader().hide()
        self.table.verticalHeader().setMinimumSectionSize(16)
        self.table.verticalHeader().setDefaultSectionSize(16)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.horizontalHeader().setFixedHeight(18)
        self.table.setFixedHeight(130)
        self.table.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.table.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        for index, name in enumerate(['DISP', 'VIN', 'CPU', 'NPU', 'RND', 'GEO', 'ETH']):
            for column, value in enumerate((name, '—', '—', '0')):
                item = QTableWidgetItem(value)
                item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                self.table.setItem(index, column, item)
        content.addWidget(self.table)
        box.addLayout(content, 1)
        metrics = QGridLayout()
        metrics.setVerticalSpacing(3)
        metrics.addWidget(self.monitor_summary, 0, 0)
        self.realtime = label('DISP 读空 0 · VIN CH0 / CH2 溢出 0 / 0', 'note')
        metrics.addWidget(self.realtime, 0, 1)
        self.monitor_note = label('等待周期：clk_mem', 'note')
        metrics.addWidget(self.monitor_note, 1, 0, 1, 2)
        for value in (self.monitor_summary, self.realtime, self.monitor_note):
            value.setWordWrap(False)
        box.addLayout(metrics)
        row.addWidget(self.monitor_card, 1)

    def _log(self, row):
        frame, box = card('会话日志')
        self.log_card = frame
        frame.setFixedWidth(280)
        header = self.panel_header(frame, box)
        header.insertWidget(1, self.button('保存', lambda: self.run(self.engine.save_log)))
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(500)
        self.log.setLineWrapMode(QPlainTextEdit.WidgetWidth)
        box.addWidget(self.log, 1)
        row.addWidget(frame)

    def _network(self):
        self.run(lambda: self.board.establish_network(self.ip.text(), 5000, self.local_ip.text()))
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

    def _choose_folder(self):
        path = QFileDialog.getExistingDirectory(self, '选择图片文件夹')
        if path:
            def select():
                self.engine.yolo.select_folder(path)
                self.image_path.setText(str(self.engine.yolo.images[0]))
                self._load_image()
                self.image_note.setText(f'{self.engine.yolo.images[0].name} · '
                                        f'1 / {len(self.engine.yolo.images)} · 等待')
            self.run(select)

    def _load_image(self):
        from PySide6.QtGui import QImageReader
        reader = QImageReader(self.image_path.text())
        image = reader.read()
        if image.isNull():
            raise ValueError(f'无法读取图片：{reader.errorString()}')
        self.static_image = image
        self.loaded_image = self.image_path.text()
        # Observe the last send without replacing a newer local selection on refresh.
        self.last_source_image = self.engine.yolo.source_image
        self.last_display = None
        self._display()

    def _send_image(self):
        def send():
            self._load_image()
            self.engine.ethernet.local_ip = self.local_ip.text()
            self.engine.ethernet.listen_console(6000)
            self.engine.yolo.send_image(self.image_path.text(), self.ip.text(), 5000,
                                        6000)
            self.last_source_image = self.engine.yolo.source_image
            self.display.setCurrentIndex(2)
            self.comparison = None
            self.comparison_result.setText('等待本次回传')
        self.run(send)

    def _camera_detection(self):
        def send():
            self.engine.ethernet.local_ip = self.local_ip.text()
            self.engine.ethernet.listen_console(6000)
            self.engine.yolo.camera_detection(self.ip.text(), 5000, 6000)
            self.display.setCurrentIndex(0)
            self.scene.setCurrentIndex(0)
        self.run(send)

    def _send_model(self):
        def send():
            self.engine.ethernet.local_ip = self.local_ip.text()
            self.engine.ethernet.listen_console(6000)
            self.engine.yolo.send_model(self.model_path.text(), self.ip.text(), 5000, 6000)
        self.run(send)
        self.model_result.setText(f'模型字节数 期望 {self.engine.yolo.image_bytes:,} B')

    def _apply_scene(self):
        def send():
            self.engine.scenes.send(['s1', 's2'][self.scene.currentIndex()])
        self.run(send)

    def _apply_output(self):
        def send():
            if not self.fps.hasAcceptableInput():
                raise ValueError('视频帧率必须为 1–60 fps')
            if not self.rate.hasAcceptableInput():
                raise ValueError('采样率必须为 10–1000 Hz')
            self.engine.scenes.send(['output_hdmi', 'output_eth', 'output_both'][
                self.output.currentIndex()])
            self.engine.scenes.send('video_fps', int(self.fps.text()))
            self.engine.scenes.send('sample_rate', int(self.rate.text()))
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

    def _video_tick(self):
        if self.isVisible():
            self._display()

    def _display(self, *_):
        state = self.engine.video.snapshot()
        frame, detections = state['frame'], state['detections']
        _, capture = self.engine.yolo.snapshot()
        mode = self.display.currentIndex()
        returned = self.engine.yolo.return_view
        if mode == 1 or (mode == 2 and returned):
            image = self.static_image
            boxes = capture[2].boxes if mode == 2 and capture is not None else ()
            if boxes:
                from core.yolo import original_boxes
                boxes = original_boxes(boxes, image.width(), image.height())
            source = ('静态原图' if mode == 1 else
                      '回传图像检查' if capture is not None else '等待图像检查回传')
            number = capture[2].frame_id if mode == 2 and capture is not None else '—'
            key = (mode, self.static_image.cacheKey(), self.generation)
            caption = (f'来源 · {source} · FRAME {number}\n'
                       f'{image.width()} × {image.height()} · {len(boxes)} 个检测框')
        elif frame is not None:
            boxes = detections.boxes if mode == 2 and detections is not None else ()
            key = (mode, frame.frame_id, boxes)
            if key == self.last_display:
                return
            image = QImage(frame.pixels, frame.width, frame.height, frame.stride,
                           QImage.Format_RGB16).copy()
            if frame is not self.displayed_frame:
                self.display_rate.add(time.monotonic())
                self.displayed_frame = frame
            caption = (f'来源 · 板端视频 · FRAME {frame.frame_id} · {state["fps"]:.1f} fps\n'
                       f'{frame.width} × {frame.height} · {len(boxes)} 个检测框')
        else:
            image, boxes, key = QImage(), (), None
            caption = '来源 · 板端视频\n等待 EDVF 视频帧'
        self.view.set_image(image, boxes)
        self.caption.setText(caption.replace('\n', ' · '))
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
                    self.table.item(index, column).setToolTip(text)
                    self.table.item(index, column).setForeground(QColor(
                        '#d24b5c' if column == 3 and port['urg_cnt'] else '#54637a'))
            values = (row['disp_underflow'], row['vin_ch0_overflow'], row['vin_ch2_overflow'])
            self.realtime.setText(f'DISP 读空 {values[0]} · VIN CH0 / CH2 溢出 '
                                  f'{values[1]} / {values[2]}')
            self.realtime.setStyleSheet(f'color:{"#d24b5c" if any(values) else "#7a8b9d"};')
            recent = [sample for sample in history
                      if sample['time_s'] > row['time_s'] - 1]
            detection_fps = sum(sample['npu_completed'] for sample in recent) * 125e6 / sum(
                sample['window_cyc'] for sample in recent)
            self.monitor_note.setText(f"NPU {row['npu_ms']:.1f} ms · 后处理 "
                                      f"{row['post_ms']:.1f} ms · 框 {row['boxes']} · "
                                      f"{detection_fps:.1f} fps · 读深 / 写浅")

    def refresh(self):
        state = self.board.status()
        connected = state['network']['peer']['done']
        board_state = state['state']
        apps = ['无', '实时识别', '图片识别', '图像处理', '图形测试', '游戏', '芯片性能测试']
        sessions = ['空闲', '启动中', '运行中', '已暂停', '停止中', '失败']
        self.phase.setText(('网口已连接' if connected else '网口未连接') +
                           ' · 板端版本 ' + (state['build'] or '—') + ' · ' +
                           apps[board_state['app']] + ' / ' + sessions[board_state['state']] +
                           (f' · {STATUS[board_state["error"]]}' if board_state['error'] else ''))
        self.phase.setWordWrap(True)
        new_state = self.state_generation != self.board.state_generation
        self.state_generation = self.board.state_generation
        self.sync_detection(board_state, new_state)
        for index, (key, title) in enumerate(zip(('listen', 'win3', 'peer', 'data'),
                ('01 · 监听 UDP 6000', '02 · 连接请求已发送', '03 · 板端已连接',
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
        self.peer.setText('板端版本 · ' + (state['build'] or '—'))
        self.processing.refresh(new_state)
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
                               (tx['error'] or tx.get('phase', '发送中' if tx['active'] else '就绪')))
        waiting = self.engine.yolo.capture_pending
        self.send_image.setEnabled(not tx['active'] and not waiting)
        self.send_model.setEnabled(not tx['active'] and not waiting)
        self.choose_folder.setEnabled(not tx['active'] and not waiting)
        self.cancel_image.setEnabled(waiting or tx['active'])
        yolo = self.engine.yolo
        self.previous_image.setEnabled(not tx['active'] and not waiting and yolo.image_index > 0)
        self.next_image.setEnabled(not tx['active'] and not waiting and
                                   yolo.image_index + 1 < len(yolo.images))
        if yolo.source_image:
            self.image_note.setText(f'{Path(yolo.source_image).name} · '
                                    f'{yolo.image_index + 1} / {len(yolo.images)} · '
                                    f'{yolo.image_status}')
        self.image_camera.setEnabled(not tx['active'] and not waiting)
        self.video_camera.setEnabled(not tx['active'] and not waiting)
        self.apply_scene.setEnabled(not tx['active'] and not waiting)
        source_image = self.engine.yolo.source_image
        if source_image is not None and source_image != self.last_source_image:
            self.image_path.setText(source_image)
            self.run(self._load_image)
        generation, capture = self.engine.yolo.snapshot()
        if (not tx['active'] and generation != self.generation and
                self.engine.yolo.error is not None):
            self.generation = generation
            self.capture_status.setText(self.engine.yolo.error +
                                       f' · 失败 {self.engine.yolo.failed} 张')
        elif not tx['active'] and capture is not None and generation != self.generation:
            self.generation = generation
            self.last_display = None
            self.board.log(f'YOLO 回传完整：FRAME {capture[2].frame_id} · '
                           f'{len(capture[2].boxes)} 个框')
            self.capture_status.setText(f'FRAME {capture[2].frame_id} · '
                                        f'{len(capture[2].boxes)} 个检测框；回传完整')
            if self.engine.yolo.timings:
                timing = self.engine.yolo.timings[-1]
                fps = len(self.engine.yolo.timings) / sum(t['seconds'] for t in
                                                          self.engine.yolo.timings)
                self.board.log(f"{timing['path']} · 往返 {timing['seconds'] * 1000:.2f} ms")
                self.capture_status.setText(self.capture_status.text() + f' · {fps:.2f} fps')
        self.compare.setEnabled(not self.comparing)
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
                    f"CH2 {result['input']['count']} B · OUTPUT {result['output']['count']} B\n"
                    f"首差异 {first_text}\n"
                    f"框差异 {result['detections']['count']} · "
                    f"参考 {result['detections']['expected']} / "
                    f"板端 {result['detections']['actual']}")
                self.board.log(self.comparison_result.text())
        self._display()
        video = self.engine.video.snapshot()
        buffer_bytes = self.engine.ethernet.status()['rx']['socketBufferBytes']
        self.video_stats.setText(
            f"接收帧率 {video['fps']:.1f} fps · "
            f"显示帧率 {self.display_rate.fps(time.monotonic()):.1f} fps · "
            f"丢弃帧数 {video['dropped']} · "
            f"接收缓冲 {buffer_bytes / 1024 / 1024:.2f} MiB · "
            f"网口跳帧 {self.engine.telemetry.status()['video_skipped']}")
        self._refresh_monitor()
        entries, _ = self.engine.get_entries(self.last_seq, 500)
        for entry in entries:
            self.log.appendPlainText(f"[{fmt_ts(entry['ts'])[:8]}] "
                                      f"{entry['dir'].upper()} {entry['text']}")
            self.last_seq = entry['seq']
