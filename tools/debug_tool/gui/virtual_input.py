"""virtual_input.py — Task T-VIN1 controller and 16:9 absolute touchpad; Qt thread."""
from PySide6.QtCore import QEvent, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QApplication, QGridLayout, QHBoxLayout, QLabel, QLineEdit, QPlainTextEdit,
    QPushButton, QTextEdit, QVBoxLayout, QWidget,
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
        self.wheel_delta = 0
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
                            (2 if event.buttons() & Qt.RightButton else 0) |
                            (4 if event.buttons() & Qt.MiddleButton else 0))
        self.panel.send()

    def mousePressEvent(self, event):
        self.setFocus()
        self.mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self.mouseMoveEvent(event)

    def wheelEvent(self, event):
        self.wheel_delta += event.angleDelta().y()
        steps = int(self.wheel_delta / 120)
        self.wheel_delta -= steps * 120
        self.panel.wheel = (self.panel.wheel - steps) & 255
        self.panel.send()
        event.accept()

    def contextMenuEvent(self, event):
        event.accept()


class VirtualInputPanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine, self.toast = engine, toast
        self.pressed = set()
        self.x = self.y = self.mouse = self.wheel = 0
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
        connection.addWidget(QLabel('本机地址'))
        self.local_ip = QLineEdit(self.engine.ethernet.local_ip)
        self.local_ip.setFixedWidth(130)
        connection.addWidget(self.local_ip)
        self.connect_button = QPushButton('建立网口连接')
        self.connect_button.clicked.connect(self.connect_network)
        connection.addWidget(self.connect_button)
        layout.addLayout(connection)
        note = QLabel('面板打开即可使用快捷键；填写地址时交给输入框。看着 HDMI 光标操作触控板。')
        note.setWordWrap(True)
        layout.addWidget(note)
        controls = QHBoxLayout()
        grid = QGridLayout()
        self.buttons = {}
        positions = [('up', '↑  W/↑', 0, 1), ('left', '←  A/←', 1, 0),
                     ('down', '↓  S/↓', 1, 1), ('right', '→  D/→', 1, 2),
                     ('a', 'A  J', 0, 3), ('b', 'B  K', 1, 3),
                     ('select', 'Select  U', 0, 4), ('start', 'Start  I', 1, 4),
                     ('enter', '确认  Enter', 0, 5), ('esc', '返回  Esc', 1, 5),
                     ('next', 'Next  Tab', 0, 6), ('prev', 'Prev  Shift+Tab', 1, 6)]
        for key, text, row, column in positions:
            button = QPushButton(text)
            self.buttons[key] = button
            button.setMinimumWidth(button.fontMetrics().horizontalAdvance(text) + 32)
            button.setStyleSheet(
                'QPushButton:pressed { background: #2458cc; color: #ffffff; '
                'border: 2px solid #173c94; }')
            button.setMinimumHeight(36)
            button.setFocusPolicy(Qt.NoFocus)
            button.pressed.connect(lambda key=key: self.button(key, True))
            button.released.connect(lambda key=key: self.button(key, False))
            grid.addWidget(button, row, column)
        controls.addLayout(grid)
        controls.addStretch()
        layout.addLayout(controls)
        help_text = QLabel('方向键 / WASD 移动 · J / K 为 A / B · U / I 为 Select / Start\n'
                           'Enter 确认 · Esc 返回 · Tab 下一项 · Shift+Tab 上一项\n'
                           '滚轮切换焦点 · 中键确认')
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
            self.engine.board.establish_network(self.ip.text(), 5000, self.local_ip.text())
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
        names = {item[1] for item in self.pressed}
        for name, button in self.buttons.items():
            button.setDown(name in names)
        keys = sum(1 << KEYS.index(key) for key in names)
        self.coordinates.setText(f'X {self.x} / 1279     Y {self.y} / 719     '
                                 f'左键 {"●" if self.mouse & 1 else "○"}     '
                                 f'右键 {"●" if self.mouse & 2 else "○"}     '
                                 f'中键 {"●" if self.mouse & 4 else "○"}     滚轮 {self.wheel}')
        try:
            self.engine.virtual_input.update(keys, self.x, self.y, self.mouse, self.wheel)
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
        in_window = focus is not None and focus.window() is self.window()
        editing = isinstance(focus, (QLineEdit, QPlainTextEdit, QTextEdit))
        if event.type() == QEvent.WindowDeactivate and obj is self.window():
            if self.pressed or self.mouse:
                self.pressed.clear()
                self.mouse = 0
                self.send()
        if (self.isVisible() and in_window and
                event.type() in (QEvent.KeyPress, QEvent.KeyRelease)):
            key = event.key()
            if key in KEY_MAP or key == Qt.Key_Backtab:
                code = Qt.Key_Tab if key == Qt.Key_Backtab else key
                releasing = event.type() == QEvent.KeyRelease
                held = any(item[0] == code for item in self.pressed)
                if editing and not (releasing and held):
                    return super().eventFilter(obj, event)
                if not event.isAutoRepeat():
                    previous = (key == Qt.Key_Backtab or
                                (key == Qt.Key_Tab and event.modifiers() & Qt.ShiftModifier))
                    name = 'prev' if previous else KEY_MAP[key]
                    token = (code, name)
                    if event.type() == QEvent.KeyPress:
                        self.pressed.add(token)
                    else:
                        self.pressed = {item for item in self.pressed if item[0] != token[0]}
                    self.send()
                return True
        return super().eventFilter(obj, event)
