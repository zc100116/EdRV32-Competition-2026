"""demo.py — live-demo L1/L3 controls and board-owned status; GUI clock."""
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
                               QLabel, QPushButton, QLineEdit, QGroupBox)
from core.demo import SCENES, CHAPTERS, PRESETS


class DemoPanel(QWidget):
    def __init__(self, engine):
        super().__init__()
        self.engine = engine
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 20, 28, 20)
        title = QLabel('现场演示')
        title.setStyleSheet('font-size: 26px; font-weight: 700; color: #173454')
        layout.addWidget(title)
        layout.addWidget(QLabel('自研 NPU → 落地应用 → 自研渲染器 → 体感交互 → 自研 CPU'))
        self.status = QLabel()
        self.status.setStyleSheet('font-size: 18px; padding: 14px; background: #e3edff')
        layout.addWidget(self.status)
        scenes = QGroupBox('场景目录 · 10 个场景')
        grid = QGridLayout(scenes)
        self.buttons = []
        for index, (chapter, name) in enumerate(zip(CHAPTERS, SCENES)):
            button = QPushButton(f'{index + 1:02d}  {chapter}\n{name}')
            button.setMinimumHeight(66)
            button.clicked.connect(lambda checked=False, n=index + 1: self.send(0, n))
            grid.addWidget(button, index // 5, index % 5)
            self.buttons.append(button)
        layout.addWidget(scenes)
        navigation = QHBoxLayout()
        for label, action in (('上一场景', 2), ('下一场景', 1), ('回到目录', 4)):
            button = QPushButton(label)
            button.clicked.connect(lambda checked=False, n=action: self.send(n, 0))
            navigation.addWidget(button)
            self.buttons.append(button)
        layout.addLayout(navigation)
        presets = QGroupBox('识别前处理')
        row = QHBoxLayout(presets)
        for index, label in enumerate(PRESETS):
            button = QPushButton(f'{index} · {label}')
            button.clicked.connect(lambda checked=False, n=index: self.send(3, n))
            row.addWidget(button)
            self.buttons.append(button)
        layout.addWidget(presets)
        phone = QGroupBox('手机中继 · TCP 47633')
        row = QHBoxLayout(phone)
        self.address = QLineEdit()
        self.address.setPlaceholderText('手机遥控界面顶部的热点地址')
        row.addWidget(self.address)
        connect = QPushButton('连接手机')
        connect.clicked.connect(lambda: engine.phone_relay.connect(self.address.text()))
        row.addWidget(connect)
        layout.addWidget(phone)
        self.relay_status = QLabel()
        self.relay_status.setWordWrap(True)
        layout.addWidget(self.relay_status)
        self.error = QLabel()
        self.error.setWordWrap(True)
        self.error.setStyleSheet('color: #bc3040')
        layout.addWidget(self.error)
        layout.addStretch()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(100)
        self.refresh()

    def send(self, action, arg):
        try:
            self.engine.ethernet.showcase.demo(action, arg)
            self.error.setText('')
        except (RuntimeError, OSError, ValueError) as exc:
            self.error.setText(str(exc))

    def refresh(self):
        status = self.engine.board.status()
        state = status['state']
        scene = state['demo_scene']
        name = ('未进入演示' if scene == 0 else '演示目录' if scene == 255
                else f'{scene}/10 · {SCENES[scene - 1]}')
        self.status.setText(f"当前场景：{name}    档位：{state['preset']}    亮度：{state['luma']}")
        from core.showcase import DEMO
        enabled = (status['network']['peer']['done'] and
                   DEMO not in self.engine.ethernet.showcase.pending)
        for button in self.buttons:
            button.setEnabled(enabled)
        relay = self.engine.phone_relay
        self.relay_status.setText(('手机已连接' if relay.connected else '手机未连接') +
                                  ' · 最小化后照常转发\n' + relay.error)
        if status['error']:
            self.error.setText(status['error'])
