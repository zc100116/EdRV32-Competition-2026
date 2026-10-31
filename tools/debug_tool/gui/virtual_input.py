"""virtual_input.py — Task T-VIN1 controller and 16:9 absolute touchpad; Qt thread."""
from PySide6.QtCore import QEvent, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QApplication, QGridLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton, QVBoxLayout, QWidget,
)
from core.virtual_input import KEYS, channel

KEY_MAP = {
    Qt.Key_Up: 'up', Qt.Key_W: 'up', Qt.Key_Down: 'down', Qt.Key_S: 'down',
    Qt.Key_Left: 'left', Qt.Key_A: 'left', Qt.Key_Right: 'right', Qt.Key_D: 'right',
    Qt.Key_J: 'a', Qt.Key_K: 'b', Qt.Key_U: 'select', Qt.Key_I: 'start',
    Qt.Key_Return: 'enter', Qt.Key_Enter: 'enter', Qt.Key_Escape: 'esc', Qt.Key_Tab: 'next',
}


class Touchpad(QWidget):
    def __init__(self, panel):
        super().__init__()
        self.panel = panel
        self.setMouseTracking(True)
        self.setMinimumSize(320, 180)
        self.setFocusPolicy(Qt.ClickFocus)

    def area(self):
        width = min(self.width(), self.height() * 16 / 9)
        height = width * 9 / 16
        return QRectF((self.width() - width) / 2, (self.height() - height) / 2, width, height)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QColor('#c5d4ef'))
        painter.setBrush(QColor('#ffffff'))
        painter.drawRoundedRect(self.area(), 12, 12)

    def mouseMoveEvent(self, event):
        area = self.area()
        self.panel.x = round(max(0, min(1, (event.position().x() - area.x()) /
                                         (area.width() - 1))) * 1279)
        self.panel.y = round(max(0, min(1, (event.position().y() - area.y()) /
                                         (area.height() - 1))) * 719)
        self.panel.mouse = ((1 if event.buttons() & Qt.LeftButton else 0) |
                            (2 if event.buttons() & Qt.RightButton else 0))
        self.panel.send()

    def mousePressEvent(self, event):
        self.setFocus()
        self.mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self.mouseMoveEvent(event)

    def contextMenuEvent(self, event):
        event.accept()


class VirtualInputPanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine, self.toast = engine, toast
        self.pressed = set()
        self.x = self.y = self.mouse = 0
        self.setFocusPolicy(Qt.StrongFocus)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(32, 18, 32, 18)
        title = QLabel('虚拟输入')
        title.setStyleSheet('font-size:22px;font-weight:700;color:#263e62;')
        layout.addWidget(title)
        self.channel = QLabel()
        connection = QHBoxLayout()
        connection.addWidget(self.channel, 1)
        connection.addWidget(QLabel('设备地址'))
        self.ip = QLineEdit(engine.board.network_endpoint[0])
        self.ip.setFixedWidth(150)
        connection.addWidget(self.ip)
        self.connect_button = QPushButton('建立网口连接')
        self.connect_button.clicked.connect(self.connect_network)
        connection.addWidget(self.connect_button)
        layout.addLayout(connection)
        note = QLabel('点击面板启用快捷键。看着 HDMI 上的光标操作，下方触控板对应完整画面。')
        note.setWordWrap(True)
        layout.addWidget(note)
        controls = QHBoxLayout()
        grid = QGridLayout()
        positions = [('up', '↑', 0, 1), ('left', '←', 1, 0), ('down', '↓', 1, 1),
                     ('right', '→', 1, 2), ('a', 'A · J', 0, 4), ('b', 'B · K', 1, 4),
                     ('select', 'Select · U', 0, 5), ('start', 'Start · I', 1, 5),
                     ('enter', 'Enter', 0, 6), ('esc', 'Esc / 返回', 1, 6)]
        for key, text, row, column in positions:
            button = QPushButton(text)
            button.setMinimumWidth(80)
            button.setMinimumHeight(36)
            button.setFocusPolicy(Qt.NoFocus)
            button.pressed.connect(lambda key=key: self.button(key, True))
            button.released.connect(lambda key=key: self.button(key, False))
            grid.addWidget(button, row, column)
        controls.addLayout(grid)
        controls.addStretch()
        layout.addLayout(controls)
        help_text = QLabel('方向键 / WASD 移动 · J / K 为 A / B · U / I 为 Select / Start\n'
                           'Enter 确认 · Esc 返回 · Tab 下一项 · Shift+Tab 上一项')
        help_text.setWordWrap(True)
        layout.addWidget(help_text)
        self.pad = Touchpad(self)
        layout.addWidget(self.pad, 1)
        self.coordinates = QLabel('X 0 / 1279     Y 0 / 719     左键 ○     右键 ○')
        layout.addWidget(self.coordinates)
        QApplication.instance().installEventFilter(self)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(200)
        self.refresh()

    def connect_network(self):
        try:
            self.engine.board.establish_network(self.ip.text(), 5000)
        except (OSError, ValueError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)
        self.setFocus()
        self.refresh()

    def refresh(self):
        self.channel.setText('当前通道 · ' + channel(self.engine))

    def button(self, key, down):
        self.setFocus()
        token = ('screen', key)
        if down:
            self.pressed.add(token)
        else:
            self.pressed.discard(token)
        self.send()

    def send(self):
        keys = sum(1 << KEYS.index(key) for key in {item[1] for item in self.pressed})
        self.coordinates.setText(f'X {self.x} / 1279     Y {self.y} / 719     '
                                 f'左键 {"●" if self.mouse & 1 else "○"}     '
                                 f'右键 {"●" if self.mouse & 2 else "○"}')
        try:
            self.engine.virtual_input.update(keys, self.x, self.y, self.mouse)
        except (OSError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)
            self.engine.board.fail(str(exc))

    def hideEvent(self, event):
        if self.pressed or self.mouse:
            self.pressed.clear()
            self.mouse = 0
            self.send()
        super().hideEvent(event)

    def eventFilter(self, obj, event):
        focus = QApplication.focusWidget()
        inside = focus is self or (focus is not None and self.isAncestorOf(focus))
        if event.type() == QEvent.WindowDeactivate and obj is self.window():
            if self.pressed or self.mouse:
                self.pressed.clear()
                self.mouse = 0
                self.send()
        if (self.isVisible() and inside and focus is not self.ip and
                event.type() in (QEvent.KeyPress, QEvent.KeyRelease)):
            key = event.key()
            if key in KEY_MAP or key == Qt.Key_Backtab:
                if not event.isAutoRepeat():
                    name = ('prev' if key == Qt.Key_Backtab else KEY_MAP[key])
                    token = (Qt.Key_Tab if key == Qt.Key_Backtab else key, name)
                    if event.type() == QEvent.KeyPress:
                        self.pressed.add(token)
                    else:
                        self.pressed = {item for item in self.pressed if item[0] != token[0]}
                    self.send()
                return True
        return super().eventFilter(obj, event)
