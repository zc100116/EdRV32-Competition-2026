"""processing.py — P5 8.3 item switches and board-owned parameters; Qt thread."""
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QFormLayout, QGroupBox, QLabel, QPushButton,
    QSpinBox, QVBoxLayout, QWidget,
)
from core.processing import DEFAULTS, ITEMS, RANGES

TITLES = dict(brightness='亮度', contrast='对比度（256 = 1 倍）', gamma_tenths='伽马（十分值）',
              stage1='滤波类型', stage2='滤波类型', threshold='阈值', angle='角度（°）',
              scale_percent='比例（%）', translate_x='水平平移（像素）', translate_y='垂直平移（像素）')


class ProcessingPanel(QWidget):
    def __init__(self, control, run):
        super().__init__()
        self.control, self.run = control, run
        self.inputs = {}
        self.switches = []
        self.last_state = None
        self.timer = QTimer(self)
        self.timer.setSingleShot(True)
        self.timer.setInterval(200)
        self.timer.timeout.connect(lambda: self.run(self.send))
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        note = QLabel('关闭功能时保留参数。修改后整组发送，显示值以板端状态为准。')
        note.setWordWrap(True)
        root.addWidget(note)
        reset = QPushButton('全部恢复默认')
        reset.clicked.connect(lambda: self.reset())
        root.addWidget(reset)
        for bit, (title, fields) in enumerate(ITEMS):
            if bit in (0, 7):
                flow = QLabel('PIX：亮度 / 对比度 → 伽马 → S1 → S2 → 灰度 → 二值化 → 反色'
                              if bit == 0 else '↓ GEO：旋转 → 缩放 → 平移 → 水平镜像 → 垂直镜像')
                flow.setWordWrap(True)
                root.addWidget(flow)
            group = QGroupBox(title)
            form = QFormLayout(group)
            form.setRowWrapPolicy(QFormLayout.WrapLongRows)
            switch = QCheckBox('启用')
            switch.toggled.connect(self.changed)
            self.switches.append(switch)
            form.addRow(switch)
            for key in fields:
                if key in ('stage1', 'stage2'):
                    widget = QComboBox()
                    widget.addItems(['均值', '高斯', '锐化', 'Sobel 边缘', '腐蚀', '膨胀'])
                    widget.currentIndexChanged.connect(self.changed)
                else:
                    widget = QSpinBox()
                    widget.setRange(*RANGES[key])
                    widget.lineEdit().setStyleSheet('border:0; padding:0; min-height:0;')
                    widget.valueChanged.connect(self.changed)
                form.addRow(TITLES[key], widget)
                self.inputs[key] = widget
            button = QPushButton('本项恢复默认')
            button.clicked.connect(lambda _, b=bit: self.reset(b))
            form.addRow(button)
            root.addWidget(group)
        self.view = QComboBox()
        self.view.addItems(['处理结果', '原图'])
        self.view.currentIndexChanged.connect(self.changed)
        root.addWidget(self.view)
        self.refresh()

    def changed(self, *_):
        self.timer.start()

    def values(self):
        values = dict(enabled=sum(int(w.isChecked()) << bit
                                  for bit, w in enumerate(self.switches)),
                      view=self.view.currentIndex())
        for key, widget in self.inputs.items():
            values[key] = (widget.currentIndex() + 1 if isinstance(widget, QComboBox)
                           else widget.value())
        return values

    def send(self):
        return self.control.send(self.values())

    def reset(self, bit=None):
        values = self.values()
        if bit is None:
            values = dict(DEFAULTS)
        else:
            for key in ITEMS[bit][1]:
                values[key] = DEFAULTS[key]
        self.timer.stop()
        self.run(lambda: self.control.send(values))

    def refresh(self, force=False):
        state = self.control.status()
        if not force and state == self.last_state:
            return
        self.last_state = state
        self.timer.stop()
        for bit, widget in enumerate(self.switches):
            widget.blockSignals(True)
            widget.setChecked(bool(state['enabled'] & (1 << bit)))
            widget.blockSignals(False)
        for key, widget in self.inputs.items():
            widget.blockSignals(True)
            if isinstance(widget, QComboBox):
                widget.setCurrentIndex(state[key] - 1)
            else:
                widget.setValue(state[key])
            widget.blockSignals(False)
        self.view.blockSignals(True)
        self.view.setCurrentIndex(state['view'])
        self.view.blockSignals(False)
