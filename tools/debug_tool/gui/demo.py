"""demo.py — live-demo L1/L3 controls and board-owned status; GUI clock."""
from PySide6.QtCore import QTimer, Qt
from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
                               QLabel, QPushButton, QLineEdit, QGroupBox,
                               QLayout, QScrollArea, QCheckBox, QSlider, QComboBox)
from core.demo import SCENES, PRESETS


class DemoPanel(QWidget):
    def __init__(self, engine):
        super().__init__()
        self.engine = engine
        outer = QVBoxLayout(self)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        outer.addWidget(scroll)
        content = QWidget()
        scroll.setWidget(content)
        layout = QVBoxLayout(content)
        layout.setSizeConstraint(QLayout.SetMinimumSize)
        layout.setContentsMargins(28, 20, 28, 20)
        title = QLabel('现场演示')
        title.setStyleSheet('font-size: 26px; font-weight: 700; color: #173454')
        layout.addWidget(title)
        layout.addWidget(QLabel('自研 NPU → 落地应用 → 自研图像处理 → 自研渲染器 → 体感交互 → 自研 CPU'))
        self.status = QLabel()
        self.status.setStyleSheet('font-size: 18px; padding: 14px; background: #e3edff')
        layout.addWidget(self.status)
        body = QHBoxLayout()
        body.setSpacing(18)
        layout.addLayout(body)
        controls = QWidget()
        controls_layout = QVBoxLayout(controls)
        controls_layout.setContentsMargins(0, 0, 0, 0)
        body.addWidget(controls, 3)
        scenes = QGroupBox('场景目录 · 11 个场景')
        grid = QGridLayout(scenes)
        self.buttons = []
        for index, name in enumerate(SCENES):
            button = QPushButton(f'{index + 1:02d}  {name}')
            button.setMinimumHeight(40)
            button.clicked.connect(lambda checked=False, n=index + 1: self.send(0, n))
            grid.addWidget(button, index // 3, index % 3)
            self.buttons.append(button)
        controls_layout.addWidget(scenes)
        navigation = QHBoxLayout()
        for label, action in (('上一场景', 2), ('下一场景', 1), ('回到目录', 4)):
            button = QPushButton(label)
            button.clicked.connect(lambda checked=False, n=action: self.send(n, 0))
            navigation.addWidget(button)
            self.buttons.append(button)
        controls_layout.addLayout(navigation)
        presets = QGroupBox('识别前处理')
        row = QHBoxLayout(presets)
        for index, label in enumerate(PRESETS):
            button = QPushButton(f'{index} · {label}')
            button.clicked.connect(lambda checked=False, n=index: self.send(3, n))
            row.addWidget(button)
            self.buttons.append(button)
        controls_layout.addWidget(presets)
        phone = QGroupBox('手机中继 · TCP 47633')
        row = QHBoxLayout(phone)
        self.address = QLineEdit()
        self.address.setPlaceholderText('手机遥控界面顶部的热点地址')
        row.addWidget(self.address)
        connect = QPushButton('连接手机')
        connect.clicked.connect(lambda: engine.phone_relay.connect(self.address.text()))
        row.addWidget(connect)
        controls_layout.addWidget(phone)
        self.mirror = QGroupBox('画面控件')
        self.mirror_layout = QVBoxLayout(self.mirror)
        body.addWidget(self.mirror, 2, Qt.AlignTop)
        self.ui_snapshot = None
        self.relay_status = QLabel()
        self.relay_status.setWordWrap(True)
        controls_layout.addWidget(self.relay_status)
        self.error = QLabel()
        self.error.setWordWrap(True)
        self.error.setStyleSheet('color: #bc3040')
        controls_layout.addWidget(self.error)
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
                else f'{scene}/11 · {SCENES[scene - 1]}')
        preset = "自定义" if state["preset"] == 255 else PRESETS[state["preset"]]
        self.status.setText(f"当前场景：{name}    档位：{preset}    亮度：{state['luma']}")
        from core.showcase import DEMO
        enabled = (status['network']['peer']['done'] and
                   DEMO not in self.engine.ethernet.showcase.pending)
        for button in self.buttons:
            button.setEnabled(enabled)
        self.refresh_ui()
        relay = self.engine.phone_relay
        self.relay_status.setText(('手机已连接' if relay.connected else '手机未连接') +
                                  ' · 最小化后照常转发\n' + relay.error)
        if status['error']:
            self.error.setText(status['error'])

    def act(self, ident, action, value=0):
        try:
            self.engine.ethernet.showcase.ui_act(self.ui_snapshot['revision'], ident, action, value)
            self.error.setText('')
        except (RuntimeError, OSError, ValueError) as exc:
            self.error.setText(str(exc))

    def refresh_ui(self):
        snapshot = self.engine.ethernet.showcase.ui.snapshot
        if snapshot == self.ui_snapshot:
            return
        self.ui_snapshot = snapshot
        while self.mirror_layout.count():
            widget = self.mirror_layout.takeAt(0).widget()
            widget.hide()
            widget.deleteLater()
        self.mirror.setTitle('画面控件 · ' + snapshot['title'])
        for area, title in enumerate(('页面', '抽屉')):
            group = QGroupBox(title)
            grid = QGridLayout(group)
            self.mirror_layout.addWidget(group)
            items = [item for item in snapshot['items'] if item['area'] == area]
            for index, item in enumerate(items):
                cell = QWidget()
                row = QHBoxLayout(cell)
                row.setContentsMargins(0, 0, 0, 0)
                ident = item['id']
                if item['kind'] == 0:
                    control = QPushButton(item['label'])
                    control.clicked.connect(lambda checked=False, n=ident: self.act(n, 0))
                elif item['kind'] == 1:
                    control = QCheckBox(item['label'])
                    control.setChecked(bool(item['value']))
                    control.clicked.connect(lambda checked=False, n=ident: self.act(n, 0))
                elif item['kind'] == 2:
                    if item['min'] >= item['max']:
                        control = QLabel(f"{item['label']}：{item['value']}")
                    else:
                        label = QLabel(f"{item['label']}：{item['value']}")
                        row.addWidget(label)
                        control = QSlider(Qt.Horizontal)
                        control.setRange(item['min'], item['max'])
                        control.setValue(item['value'])
                        control.valueChanged.connect(
                            lambda value, label=label, name=item['label']:
                            label.setText(f'{name}：{value}'))
                        control.sliderReleased.connect(
                            lambda n=ident, slider=control: self.act(n, 1, slider.value()))
                else:
                    row.addWidget(QLabel(item['label']))
                    control = QComboBox()
                    control.addItems(item['options'])
                    control.setPlaceholderText('未选')
                    value = item['value']
                    control.setCurrentIndex(value if 0 <= value < len(item['options']) else -1)
                    control.activated.connect(lambda value, n=ident: self.act(n, 1, value))
                row.addWidget(control)
                grid.addWidget(cell, index, 0)
