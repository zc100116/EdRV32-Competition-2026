"""PySide6 desktop UI for EdRV32 调试工具.

VOFA-style three-column layout:
  left   -- icon rail switching 连接 / 命令 / 规则 panels
  center -- classic scrolling log console + composer
  right  -- live parameter panel fed by user-defined match rules
A dedicated SoC console joins board controls, one canvas and DDR charts.
All actions go through SerialEngine, so the REST API / CLI observe and
control the exact same session. All three columns are splitter-resizable.
"""

import threading
from collections import deque

from PySide6.QtCore import Qt, QSize, QTimer
from PySide6.QtGui import QColor, QFont, QGuiApplication, QIcon, QPixmap, \
    QTextCharFormat, QTextCursor
from PySide6.QtWidgets import (
    QButtonGroup, QCheckBox, QComboBox, QDialog, QDialogButtonBox,
    QDoubleSpinBox, QFileDialog, QFormLayout, QFrame, QGridLayout,
    QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox, QProgressBar,
    QPushButton, QPlainTextEdit, QSizePolicy, QScrollArea, QSpinBox, QSplitter,
    QStackedWidget, QToolButton, QVBoxLayout, QWidget,
)

from core.engine import ENCODINGS, fmt_ts
from gui.ethernet import EthernetPanel
from gui.soc_console import SocConsole

# Lines kept in the on-screen document. The engine buffer (and saved logs)
# retain more; the visible cap only bounds the widget's layout cost.
VIEW_MAX_LINES = 1500

QSS = """
* { font-family: "Microsoft YaHei UI", "Segoe UI", sans-serif; }
QMainWindow, QWidget#root { background: #f3f5f8; }
QToolTip { background:#ffffff; color:#33404d; border:1px solid #d5dbe4;
           padding:5px 8px; }

/* ---------------- header ---------------- */
QWidget#header { background: #ffffff; border-bottom: 1px solid #e3e7ee; }
QLabel#logo {
    background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #4f8dfd, stop:1 #2f6bff);
    color: #ffffff; font-weight: 800; font-size: 17px;
    border-radius: 10px; min-width: 42px; max-width: 42px;
    min-height: 42px; max-height: 42px;
}
QLabel#appTitle { color: #1f2a37; font-size: 17px; font-weight: 700; }
QLabel#appSub { color: #9aa6b5; font-size: 11px; letter-spacing: 1px; }
QWidget#chip { background: #f4f6fa; border: 1px solid #e0e5ec;
               border-radius: 13px; }
QLabel#chipDot { border-radius: 5px; min-width:10px; max-width:10px;
                 min-height:10px; max-height:10px; }
QLabel#chipText { color: #54637a; font-size: 12px;
                  font-family: "Cascadia Mono","Consolas",monospace; }

/* ---------------- cards ---------------- */
QFrame#card { background: #ffffff; border: 1px solid #e3e7ee;
              border-radius: 12px; }
QLabel#cardTitle { color: #2f6bff; font-size: 12px; font-weight: 700;
                   letter-spacing: 2px; }

/* ---------------- buttons ---------------- */
QPushButton {
    background: #ffffff; color: #33404d; border: 1px solid #d3dae3;
    border-radius: 8px; padding: 7px 14px; font-size: 12px;
}
QPushButton:hover { background: #f0f5ff; border-color: #2f6bff;
                    color: #2f6bff; }
QPushButton:pressed { background: #d7e4ff; border-color: #2f6bff;
                      color: #2f6bff; padding: 8px 13px 6px 15px; }
QPushButton:disabled { background: #f4f6fa; color: #aab4c2;
                       border-color: #e3e7ee; }
QPushButton#primary {
    background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #4f8dfd, stop:1 #2f6bff);
    color: #ffffff; font-weight: 700; border: none;
}
QPushButton#primary:hover { background: #1f5ef0; color: #ffffff; }
QPushButton#primary:pressed { background: #1a4fd0; color: #ffffff;
                              padding: 8px 13px 6px 15px; }
QPushButton#primary:disabled { background:#d8e2f5; color:#ffffff;
                               border:none; }
QPushButton#ghost { background: #ffffff; border: 1px solid #d3dae3;
                    color: #54637a; }
QPushButton#ghost:hover { border-color: #2f6bff; color: #2f6bff;
                          background: #f0f5ff; }
QPushButton#ghost:pressed { background: #d7e4ff; border-color: #2f6bff;
                            color: #2f6bff; }
QPushButton#ghostDanger { background: #ffffff; border: 1px solid #e8c8cc;
                          color: #d24b5c; }
QPushButton#ghostDanger:hover { border-color: #d24b5c; color: #b21e33;
                                background: #fdf1f2; }
QPushButton#ghostDanger:pressed { background: #fbe0e4; border-color: #d24b5c; }
QPushButton#cmdBtn { background: #ffffff; border: 1px solid #dbe1ea;
                     color: #33404d; text-align: center; padding: 9px 6px;
                     font-size: 12px; min-height: 34px; }
QPushButton#cmdBtn:hover { border-color: #2f6bff; background: #f0f5ff;
                           color: #2f6bff; }
QPushButton#cmdBtn:pressed { background: #d7e4ff; border-color: #2f6bff;
                             color: #2f6bff; padding: 10px 5px 8px 7px; }
QPushButton#cmdAdd { background: transparent; border: 1px dashed #c3cdd9;
                     color: #8b98a9; min-height: 34px; }
QPushButton#cmdAdd:hover { border-color: #2f6bff; color: #2f6bff; }
QPushButton#cmdAdd:pressed { background: #eef4ff; border-color: #2f6bff; }
QPushButton#rowIcon { background: transparent; border: none;
                      color: #8b98a9; font-size: 13px; padding: 2px 7px;
                      border-radius: 6px; }
QPushButton#rowIcon:hover { color: #2f6bff; background: #e3edff; }
QPushButton#rowIcon:pressed { background: #c9dbfc; color: #1f5ef0; }
QPushButton#miniToggle { background: #ffffff; border: 1px solid #d3dae3;
                         color: #54637a; border-radius: 7px;
                         padding: 5px 10px; font-size: 11px; }
QPushButton#miniToggle:hover { border-color: #2f6bff; color: #2f6bff; }
QPushButton#miniToggle:pressed { background: #d7e4ff; border-color: #2f6bff;
                                 padding: 6px 9px 4px 11px; }
QPushButton#miniToggle:checked { background: #e3edff; color: #2f6bff;
                                 border-color: #2f6bff; font-weight: 700; }
QProgressBar { background: #eef1f5; border: none; border-radius: 5px;
               min-height: 10px; max-height: 10px; }
QProgressBar::chunk { background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #4f8dfd, stop:1 #2f6bff); border-radius: 5px; }
QLabel#fileLabel { color: #54637a; font-size: 11px;
                   font-family: "Cascadia Mono","Consolas",monospace; }

/* ---------------- left rail ---------------- */
QFrame#rail { background: #ffffff; border: 1px solid #e3e7ee;
              border-radius: 12px; }
QToolButton#railBtn { background: transparent; border: none;
                      border-radius: 10px; color: #7a8b9d;
                      font-size: 10px; font-weight: 600;
                      min-width: 46px; max-width: 46px;
                      min-height: 52px; max-height: 52px; }
QToolButton#railBtn:hover { background: #f0f5ff; color: #2f6bff; }
QToolButton#railBtn:pressed { background: #c9dbfc; color: #1f5ef0; }
QToolButton#railBtn:checked { background: #e3edff; color: #2f6bff; }

/* ---------------- console ---------------- */
QPlainTextEdit#console { background: #ffffff; border: none;
    border-top: 1px solid #eef1f5; border-bottom: 1px solid #eef1f5;
    font-family: "Cascadia Mono","Consolas",monospace; font-size: 13px; }
QPushButton#jumpBtn {
    background: rgba(47, 107, 255, 0.95); color: #ffffff; font-weight: 700;
    border: none; border-radius: 13px; padding: 6px 14px;
}
QPushButton#jumpBtn:hover { background: #1f5ef0; }

/* ---------------- data / rules rows ---------------- */
QFrame#paramRow { background: #f8fafc; border: 1px solid #e7ecf2;
                  border-radius: 8px; }
QLabel#paramName { color: #54637a; font-size: 11px; background:transparent; }
QLabel#paramValue { color: #1f5ef0; font-size: 15px; font-weight: 700;
                    font-family: "Cascadia Mono","Consolas",monospace;
                    background: transparent; }
QLabel#paramMeta { color: #9aa6b5; font-size: 11px; background: transparent;
                   font-family: "Cascadia Mono","Consolas",monospace; }
QLabel#ruleName { color: #33404d; font-size: 12px; font-weight: 600;
                  background: transparent; }
QLabel#rulePattern { color: #9aa6b5; font-size: 11px; background: transparent;
                     font-family: "Cascadia Mono","Consolas",monospace; }

/* ---------------- inputs ---------------- */
QLineEdit, QPlainTextEdit, QComboBox, QSpinBox, QDoubleSpinBox {
    background: #ffffff; color: #2a3442; border: 1px solid #d3dae3;
    border-radius: 8px; padding: 4px 10px; font-size: 13px;
    min-height: 30px;
    selection-background-color: #bcd3ff;
}
QComboBox { padding: 4px 8px; }
QComboBox::item { min-height: 26px; }
QComboBox#mini { min-height: 26px; padding: 2px 8px; font-size: 11px; }
QLineEdit:focus, QPlainTextEdit:focus, QComboBox:focus,
QSpinBox:focus, QDoubleSpinBox:focus { border-color: #2f6bff; }
QLineEdit:disabled, QComboBox:disabled { color: #aab4c2;
    background: #f4f6fa; }
QComboBox QAbstractItemView { background: #ffffff; color: #2a3442;
    border: 1px solid #d5dbe4; selection-background-color: #e3edff;
    selection-color: #1f5ef0; outline: none; }
QComboBox::drop-down { border: none; width: 22px; }
QLabel#fieldLabel { color: #8b98a9; font-size: 11px; }
QCheckBox { color: #54637a; font-size: 11px; spacing: 5px;
            background: transparent; }

/* ---------------- scrollbars ---------------- */
QScrollBar:vertical { background: transparent; width: 10px; margin: 2px; }
QScrollBar::handle:vertical { background: #d0d7e0; border-radius: 5px;
    min-height: 30px; }
QScrollBar::handle:vertical:hover { background: #b4bfcd; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QScrollBar:horizontal { background: transparent; height: 10px; margin: 2px; }
QScrollBar::handle:horizontal { background: #d0d7e0; border-radius: 5px;
    min-width: 30px; }
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal { width: 0; }

/* ---------------- footer / misc ---------------- */
QWidget#footer { background: #ffffff; border-top: 1px solid #e3e7ee; }
QLabel#footText { color: #8b98a9; font-size: 11px;
                  font-family: "Cascadia Mono","Consolas",monospace; }
QLabel#apiHint { color: #8b98a9; font-size: 11px;
                 font-family: "Cascadia Mono","Consolas",monospace; }
QDialog { background: #f7f9fb; }
QDialog QLabel { color: #54637a; font-size: 12px; }
QMenu { background: #ffffff; color: #33404d; border: 1px solid #d5dbe4; }
QMenu::item:selected { background: #e3edff; color: #1f5ef0; }
QScrollArea { background: transparent; }
QScrollArea > QWidget > QWidget { background: transparent; }

/* ---------------- splitters ---------------- */
QSplitter::handle:horizontal { width: 7px; background: transparent; }
QSplitter::handle:vertical { height: 7px; background: transparent; }
QSplitter::handle:hover { background: #c9d6fb; }
QSplitter::handle:pressed { background: #2f6bff; }
"""


def fmt_bytes(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0


# ------------------------------------------------------------ rail icons --
# Minimal stroke icons (Feather-style paths), tinted per button state.
def _svg_pixmap(paths, color, size=24):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
           f'height="{size}" viewBox="0 0 24 24" fill="none" '
           f'stroke="{color}" stroke-width="1.8" stroke-linecap="round" '
           f'stroke-linejoin="round">{paths}</svg>')
    pixmap = QPixmap()
    pixmap.loadFromData(svg.encode("utf-8"))
    return pixmap


def state_icon(paths):
    icon = QIcon()
    icon.addPixmap(_svg_pixmap(paths, "#7a8b9d"), QIcon.Normal, QIcon.Off)
    icon.addPixmap(_svg_pixmap(paths, "#2f6bff"), QIcon.Normal, QIcon.On)
    icon.addPixmap(_svg_pixmap(paths, "#2f6bff"), QIcon.Active, QIcon.Off)
    return icon


ICON_PLUG = ('<path d="M9 7V3M15 7V3"/><path d="M7 7h10v4a5 5 0 0 1-10 0V7z"/>'
             '<path d="M12 16v5"/>')
ICON_TERMINAL = ('<polyline points="4 17 10 11 4 5"/>'
                 '<line x1="12" y1="19" x2="20" y2="19"/>')
ICON_FILTER = ('<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 '
               '22 3"/>')

ICON_NETWORK = ('<rect x="3" y="3" width="18" height="10" rx="2"/>'
                '<path d="M12 13v4M4 21v-4h16v4M4 21h0M12 17v4M20 21h0"/>')
ICON_DASHBOARD = ('<rect x="3" y="3" width="18" height="18" rx="2"/>'
                  '<path d="M3 9h18M9 9v12M13 13h5M13 17h3"/>')


# ------------------------------------------------------------------ toast --
class Toast(QLabel):
    def __init__(self, parent):
        super().__init__(parent)
        self.hide()
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self.hide)

    def show_message(self, text, error=False):
        if error:
            self.setStyleSheet(
                "background:#fdf1f2; color:#b21e33; border:1px solid #e8a4ad;"
                "border-radius:8px; padding:8px 18px; font-size:12px;")
        else:
            self.setStyleSheet(
                "background:#eef4ff; color:#1f5ef0; border:1px solid #9dbcf9;"
                "border-radius:8px; padding:8px 18px; font-size:12px;")
        self.setText(text)
        self.adjustSize()
        parent = self.parentWidget()
        self.move((parent.width() - self.width()) // 2, 66)
        self.show()
        self.raise_()
        self._timer.start(2600)


# ------------------------------------------------------------- rx batches --
class EngineBatch:
    """RX-thread-side sink: queuing entries is O(1) and touches no Qt object,
    so a fast serial stream can never flood the GUI event queue. A QTimer on
    the GUI thread drains the list and renders the whole batch at once."""

    def __init__(self):
        self._lock = threading.Lock()
        self._pending = []

    def push(self, entry):
        with self._lock:
            self._pending.append(entry)

    def drain(self, limit=None):
        with self._lock:
            if limit is None or len(self._pending) <= limit:
                out, self._pending = self._pending, []
            else:
                out, self._pending = (self._pending[:limit],
                                      self._pending[limit:])
        return out


# --------------------------------------------------------------- console --
DIR_STYLES = {
    "rx":  ("#16a34a", "#2a3442"),
    "tx":  ("#2f6bff", "#2f6bff"),
    "sys": ("#b4821c", "#b4821c"),
}


def _fmt(color, bold=False):
    fmt = QTextCharFormat()
    fmt.setForeground(QColor(color))
    if bold:
        fmt.setFontWeight(QFont.Bold)
    return fmt


def _printable(text):
    """Display-layer sanitization: binary payloads decode to invisible
    control characters; show them as dots so they stay visible in text
    mode. The stored buffer keeps the exact decoded text (rules, logs)."""
    return "".join(c if (c.isprintable() or c in "\n\t") else "·"
                   for c in text)


class ConsoleView(QWidget):
    """Plain-text scrolling log. Batched rendering keeps fast streams smooth;
    display options (HEX/text, timestamps, direction filter) re-render the
    retained entries in place."""

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self.text = QPlainTextEdit()
        self.text.setObjectName("console")
        self.text.setReadOnly(True)
        self.text.setPlaceholderText(
            "暂无数据 — 连接串口后，收发的每一行都会打印在这里")
        self.text.setMaximumBlockCount(VIEW_MAX_LINES)
        layout.addWidget(self.text)

        self.entries = deque(maxlen=VIEW_MAX_LINES)
        self.mode = "text"        # text | hex
        self.show_ts = True
        self.dir_visible = {"rx": True, "tx": True, "sys": True}

        self._fmt_ts = _fmt("#9aa6b5")
        self._fmt_tag = {d: _fmt(c, bold=True) for d, (c, _) in
                         DIR_STYLES.items()}
        self._fmt_text = {d: _fmt(c) for d, (_, c) in DIR_STYLES.items()}
        self._fmt_default_tag = _fmt("#8b98a9", bold=True)
        self._fmt_default_text = _fmt("#2a3442")

        self.jump = QPushButton("↓ 新消息", self)
        self.jump.setObjectName("jumpBtn")
        self.jump.setCursor(Qt.PointingHandCursor)
        self.jump.hide()
        self.jump.clicked.connect(self.scroll_to_bottom)

        bar = self.text.verticalScrollBar()
        bar.valueChanged.connect(self._on_scroll)

    def _render_line(self, cursor, entry):
        direction = entry["dir"]
        if not self.dir_visible.get(direction, True):
            return
        if self.show_ts:
            cursor.insertText(f"[{fmt_ts(entry['ts'])}] ", self._fmt_ts)
        cursor.insertText(f"[{direction.upper()}] ",
                          self._fmt_tag.get(direction, self._fmt_default_tag))
        if self.mode == "hex" and entry.get("hex"):
            content = entry["hex"]
        else:
            content = _printable(entry["text"])
        cursor.insertText(
            content + "\n",
            self._fmt_text.get(direction, self._fmt_default_text))

    def append_many(self, entries):
        if not entries:
            return
        self.entries.extend(entries)
        bar = self.text.verticalScrollBar()
        near_bottom = bar.value() >= bar.maximum() - 40
        cursor = self.text.textCursor()
        cursor.movePosition(QTextCursor.End)
        cursor.beginEditBlock()
        for entry in entries:
            self._render_line(cursor, entry)
        cursor.endEditBlock()
        if near_bottom:
            self.scroll_to_bottom()
        else:
            self.jump.show()

    def rerender(self):
        self.text.clear()
        cursor = self.text.textCursor()
        cursor.beginEditBlock()
        for entry in self.entries:
            self._render_line(cursor, entry)
        cursor.endEditBlock()
        self.scroll_to_bottom()

    def set_mode(self, mode):
        self.mode = mode
        self.rerender()

    def set_timestamps(self, on):
        self.show_ts = on
        self.rerender()

    def set_dir_visible(self, direction, on):
        self.dir_visible[direction] = on
        self.rerender()

    def clear(self):
        self.entries.clear()
        self.text.clear()
        self.jump.hide()

    def scroll_to_bottom(self):
        bar = self.text.verticalScrollBar()
        bar.setValue(bar.maximum())
        self.jump.hide()

    def _on_scroll(self, value):
        bar = self.text.verticalScrollBar()
        if value >= bar.maximum() - 10:
            self.jump.hide()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.jump.adjustSize()
        self.jump.move(self.width() - self.jump.width() - 18,
                       self.height() - self.jump.height() - 14)


# -------------------------------------------------------------- commands --
class CommandDialog(QDialog):
    def __init__(self, parent, title, command=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(360)
        form = QFormLayout(self)
        form.setContentsMargins(18, 18, 18, 18)
        form.setSpacing(10)
        self.label_edit = QLineEdit()
        self.label_edit.setPlaceholderText("例如：CoreMark")
        self.payload_edit = QPlainTextEdit()
        self.payload_edit.setPlaceholderText("例如：6")
        self.payload_edit.setFixedHeight(64)
        self.ending_edit = QComboBox()
        for value, text in (("cr", r"回车 \r"), ("lf", r"换行 \n"),
                            ("crlf", r"\r\n"), ("none", "无行尾")):
            self.ending_edit.addItem(text, value)
        if command:
            self.label_edit.setText(command["label"])
            self.payload_edit.setPlainText(command["payload"])
            idx = self.ending_edit.findData(command.get("ending", "cr"))
            if idx >= 0:
                self.ending_edit.setCurrentIndex(idx)
        form.addRow("名称", self.label_edit)
        form.addRow("发送内容", self.payload_edit)
        form.addRow("行尾", self.ending_edit)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Ok).setText("保存")
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        form.addRow(buttons)

    def value(self):
        return {"label": self.label_edit.text().strip(),
                "payload": self.payload_edit.toPlainText(),
                "ending": self.ending_edit.currentData()}


class CommandsPanel(QFrame):
    def __init__(self, engine, toast, parent=None):
        super().__init__(parent)
        self.engine = engine
        self.toast = toast
        self.setObjectName("card")
        self._snapshot = ""
        self._buttons = []
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)
        head = QHBoxLayout()
        title = QLabel("快捷命令")
        title.setObjectName("cardTitle")
        head.addWidget(title)
        head.addStretch(1)
        import_btn = QPushButton("导入")
        import_btn.setObjectName("ghost")
        import_btn.setFixedHeight(26)
        import_btn.setToolTip("从 JSON 文件加载命令配置（替换当前列表）")
        import_btn.clicked.connect(self._import)
        export_btn = QPushButton("导出")
        export_btn.setObjectName("ghost")
        export_btn.setFixedHeight(26)
        export_btn.setToolTip("把当前命令配置保存为 JSON 文件")
        export_btn.clicked.connect(self._export)
        head.addWidget(import_btn)
        head.addWidget(export_btn)
        root.addLayout(head)

        scroll = QScrollArea()
        scroll.setObjectName("cmdScroll")
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        host = QWidget()
        host.setObjectName("cmdHost")
        self.grid = QGridLayout(host)
        self.grid.setSpacing(10)
        self.grid.setContentsMargins(2, 2, 2, 2)
        self.grid.setAlignment(Qt.AlignTop)
        scroll.setWidget(host)
        root.addWidget(scroll, 1)

        hint = QLabel("点击即发送 · 右键可编辑 / 删除 · 配置保存在 commands.json")
        hint.setObjectName("apiHint")
        hint.setWordWrap(True)
        root.addWidget(hint)
        self.reload(force=True)

    def reload(self, force=False):
        import json as _json
        commands = self.engine.list_commands()
        snap = _json.dumps(commands, ensure_ascii=False)
        if not force and snap == self._snapshot:
            return
        self._snapshot = snap
        for btn in self._buttons:
            self.grid.removeWidget(btn)
            btn.deleteLater()
        self._buttons = []
        col_count = 2
        for i, cmd in enumerate(commands):
            btn = QPushButton(cmd["label"])
            btn.setObjectName("cmdBtn")
            btn.setCursor(Qt.PointingHandCursor)
            btn.setToolTip(f"发送: {cmd['payload']!r} ({cmd.get('ending','cr')})")
            btn.clicked.connect(lambda _=False, c=cmd: self._fire(c))
            btn.setContextMenuPolicy(Qt.CustomContextMenu)
            btn.customContextMenuRequested.connect(
                lambda pos, c=cmd, b=btn: self._menu(b, c, pos))
            self.grid.addWidget(btn, i // col_count, i % col_count)
            self._buttons.append(btn)
        add = QPushButton("＋ 新建命令")
        add.setObjectName("cmdAdd")
        add.setCursor(Qt.PointingHandCursor)
        add.clicked.connect(self._add)
        next_row = (len(commands) + col_count - 1) // col_count
        self.grid.addWidget(add, next_row, 0, 1, col_count)
        self._buttons.append(add)

    # Buttons stay enabled even when disconnected so right-click edit/delete
    # always works; clicking send while disconnected shows a toast in _fire.
    def _fire(self, cmd):
        try:
            self.engine.send_command(cmd["id"])
        except RuntimeError:
            self.toast.show_message("串口未连接", error=True)

    def _menu(self, button, cmd, pos):
        from PySide6.QtWidgets import QMenu
        menu = QMenu(self)
        act_edit = menu.addAction("编辑")
        act_del = menu.addAction("删除")
        action = menu.exec(button.mapToGlobal(pos))
        if action is act_edit:
            dialog = CommandDialog(self, "编辑命令", cmd)
            if dialog.exec() == QDialog.Accepted:
                value = dialog.value()
                if not value["label"]:
                    self.toast.show_message("名称不能为空", error=True)
                    return
                self.engine.upsert_command(value, cmd["id"])
                self.reload(force=True)
        elif action is act_del:
            answer = QMessageBox.question(
                self, "删除命令", f"确定删除「{cmd['label']}」吗？")
            if answer == QMessageBox.Yes:
                self.engine.delete_command(cmd["id"])
                self.reload(force=True)

    def _export(self):
        path, _ = QFileDialog.getSaveFileName(
            self, "导出命令配置", "commands.json", "JSON 文件 (*.json)")
        if not path:
            return
        try:
            result = self.engine.export_commands(path)
            self.toast.show_message(f"已导出 {result['count']} 条命令")
        except OSError as exc:
            self.toast.show_message(f"导出失败:{exc}", error=True)

    def _import(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "导入命令配置", "", "JSON 文件 (*.json)")
        if not path:
            return
        current = len(self.engine.list_commands())
        answer = QMessageBox.question(
            self, "导入命令配置",
            f"导入将替换当前 {current} 条命令，继续？")
        if answer != QMessageBox.Yes:
            return
        try:
            commands = self.engine.import_commands(path)
        except ValueError as exc:
            self.toast.show_message(f"导入失败:{exc}", error=True)
            return
        self.reload(force=True)
        self.toast.show_message(f"已导入 {len(commands)} 条命令")

    def _add(self):
        dialog = CommandDialog(self, "新建命令")
        if dialog.exec() == QDialog.Accepted:
            value = dialog.value()
            if not value["label"]:
                self.toast.show_message("名称不能为空", error=True)
                return
            try:
                self.engine.upsert_command(value)
            except ValueError as exc:
                self.toast.show_message(str(exc), error=True)
                return
            self.reload(force=True)


# ----------------------------------------------------------------- rules --
class RuleDialog(QDialog):
    def __init__(self, parent, title, rule=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(400)
        form = QFormLayout(self)
        form.setContentsMargins(18, 18, 18, 18)
        form.setSpacing(10)
        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("例如：温度")
        self.pattern_edit = QLineEdit()
        self.pattern_edit.setPlaceholderText(r"例如：TEMP=(\d+)")
        self.pattern_edit.setStyleSheet(
            'font-family:"Cascadia Mono","Consolas",monospace;')
        self.key_group = QSpinBox()
        self.key_group.setRange(0, 9)
        self.key_group.setToolTip("0 表示单一参数；>0 时该捕获组作为参数键，"
                                  "一条规则可展开成多个参数")
        self.value_group = QSpinBox()
        self.value_group.setRange(1, 9)
        self.value_group.setValue(1)
        self.base_combo = QComboBox()
        self.base_combo.addItem("10 进制", 10)
        self.base_combo.addItem("16 进制", 16)
        self.scale_edit = QDoubleSpinBox()
        self.scale_edit.setDecimals(9)
        self.scale_edit.setRange(1e-9, 1e12)
        self.scale_edit.setValue(1.0)
        self.unit_edit = QLineEdit()
        self.unit_edit.setPlaceholderText("例如：℃ / % / V，可留空")
        self.enabled_edit = QCheckBox("启用该规则")
        self.enabled_edit.setChecked(True)
        if rule:
            self.name_edit.setText(rule.get("name", ""))
            self.pattern_edit.setText(rule.get("pattern", ""))
            self.key_group.setValue(int(rule.get("keyGroup") or 0))
            self.value_group.setValue(int(rule.get("valueGroup") or 1))
            self.base_combo.setCurrentIndex(
                1 if rule.get("base") == 16 else 0)
            self.scale_edit.setValue(float(rule.get("scale", 1)))
            self.unit_edit.setText(rule.get("unit", ""))
            self.enabled_edit.setChecked(bool(rule.get("enabled", True)))
        form.addRow("名称", self.name_edit)
        form.addRow("正则表达式", self.pattern_edit)
        form.addRow("键捕获组", self.key_group)
        form.addRow("值捕获组", self.value_group)
        form.addRow("数值进制", self.base_combo)
        form.addRow("缩放系数", self.scale_edit)
        form.addRow("单位", self.unit_edit)
        form.addRow("", self.enabled_edit)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Ok).setText("保存")
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        form.addRow(buttons)

    def value(self):
        return {"name": self.name_edit.text().strip(),
                "pattern": self.pattern_edit.text(),
                "keyGroup": self.key_group.value(),
                "valueGroup": self.value_group.value(),
                "base": self.base_combo.currentData(),
                "scale": self.scale_edit.value(),
                "unit": self.unit_edit.text().strip(),
                "enabled": self.enabled_edit.isChecked()}


class RulesPanel(QFrame):
    """Match-rule manager: RX lines matching a rule's regex publish a live
    parameter to the data panel."""

    def __init__(self, engine, toast, parent=None):
        super().__init__(parent)
        self.engine = engine
        self.toast = toast
        self.setObjectName("card")
        self._snapshot = ""
        self._rows = []
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)
        head = QHBoxLayout()
        title = QLabel("数据规则")
        title.setObjectName("cardTitle")
        head.addWidget(title)
        head.addStretch(1)
        add_btn = QPushButton("新建")
        add_btn.setObjectName("ghost")
        add_btn.setFixedHeight(26)
        add_btn.clicked.connect(self._add)
        head.addWidget(add_btn)
        root.addLayout(head)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        host = QWidget()
        self.rows_layout = QVBoxLayout(host)
        self.rows_layout.setContentsMargins(2, 2, 2, 2)
        self.rows_layout.setSpacing(8)
        self.rows_layout.setAlignment(Qt.AlignTop)
        scroll.setWidget(host)
        root.addWidget(scroll, 1)

        hint = QLabel("RX 行命中正则即提取数值并显示在右侧数据面板 · "
                      "配置保存在 rules.json")
        hint.setObjectName("apiHint")
        hint.setWordWrap(True)
        root.addWidget(hint)
        self.reload(force=True)

    def reload(self, force=False):
        import json as _json
        rules = self.engine.list_rules()
        snap = _json.dumps(rules, ensure_ascii=False, sort_keys=True)
        if not force and snap == self._snapshot:
            return
        self._snapshot = snap
        for row in self._rows:
            self.rows_layout.removeWidget(row)
            row.deleteLater()
        self._rows = []
        for rule in rules:
            self.rows_layout.addWidget(self._make_row(rule))

    def _make_row(self, rule):
        row = QFrame()
        row.setObjectName("paramRow")
        layout = QHBoxLayout(row)
        layout.setContentsMargins(10, 8, 6, 8)
        layout.setSpacing(6)
        checkbox = QCheckBox()
        checkbox.setChecked(bool(rule.get("enabled", True)))
        checkbox.setToolTip("启用 / 停用")
        checkbox.toggled.connect(
            lambda on, r=rule: self._toggle(r, on))
        layout.addWidget(checkbox)
        text_box = QVBoxLayout()
        text_box.setSpacing(1)
        name = QLabel(rule["name"])
        name.setObjectName("ruleName")
        name.setToolTip(name.text())
        name.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        pattern = QLabel("/" + rule["pattern"] + "/")
        pattern.setObjectName("rulePattern")
        pattern.setToolTip(pattern.text())
        pattern.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        text_box.addWidget(name)
        text_box.addWidget(pattern)
        layout.addLayout(text_box, 1)
        edit_btn = QPushButton("✎")
        edit_btn.setObjectName("rowIcon")
        edit_btn.setToolTip("编辑")
        edit_btn.clicked.connect(lambda _=False, r=rule: self._edit(r))
        del_btn = QPushButton("✕")
        del_btn.setObjectName("rowIcon")
        del_btn.setToolTip("删除")
        del_btn.clicked.connect(lambda _=False, r=rule: self._delete(r))
        layout.addWidget(edit_btn)
        layout.addWidget(del_btn)
        self._rows.append(row)
        return row

    def _toggle(self, rule, on):
        body = dict(rule)
        body["enabled"] = bool(on)
        try:
            self.engine.upsert_rule(body, rule["id"])
        except ValueError as exc:
            self.toast.show_message(str(exc), error=True)
        self.reload(force=True)

    def _edit(self, rule):
        dialog = RuleDialog(self, "编辑规则", rule)
        if dialog.exec() == QDialog.Accepted:
            self._save(dialog.value(), rule["id"])

    def _delete(self, rule):
        answer = QMessageBox.question(
            self, "删除规则", f"确定删除规则「{rule['name']}」吗？")
        if answer == QMessageBox.Yes:
            self.engine.delete_rule(rule["id"])
            self.reload(force=True)

    def _add(self):
        dialog = RuleDialog(self, "新建规则")
        if dialog.exec() == QDialog.Accepted:
            self._save(dialog.value(), None)

    def _save(self, value, rid):
        if not value["name"]:
            self.toast.show_message("名称不能为空", error=True)
            return
        try:
            self.engine.upsert_rule(value, rid)
        except ValueError as exc:
            self.toast.show_message(str(exc), error=True)
            return
        self.reload(force=True)


# ------------------------------------------------------------ data panel --
class DataPanel(QFrame):
    """Live parameter view: each matched rule key becomes one row showing
    the latest value, raw capture, update count and time (VOFA 数据面板)."""

    def __init__(self, engine, toast, parent=None):
        super().__init__(parent)
        self.engine = engine
        self.toast = toast
        self.setObjectName("card")
        self._rows = {}
        self._snapshot = None
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)
        head = QHBoxLayout()
        title = QLabel("提取数据")
        title.setObjectName("cardTitle")
        head.addWidget(title)
        head.addStretch(1)
        self.count_label = QLabel("0 项")
        self.count_label.setObjectName("apiHint")
        head.addWidget(self.count_label)
        clear_btn = QPushButton("清空")
        clear_btn.setObjectName("ghost")
        clear_btn.setFixedHeight(26)
        clear_btn.clicked.connect(self._clear)
        head.addWidget(clear_btn)
        root.addLayout(head)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        host = QWidget()
        self.rows_layout = QVBoxLayout(host)
        self.rows_layout.setContentsMargins(2, 2, 2, 2)
        self.rows_layout.setSpacing(8)
        self.rows_layout.setAlignment(Qt.AlignTop)
        scroll.setWidget(host)
        root.addWidget(scroll, 1)

        hint = QLabel("RX 数据命中规则后自动出现在这里 · "
                      "API: GET /api/params")
        hint.setObjectName("apiHint")
        hint.setWordWrap(True)
        root.addWidget(hint)

    def _clear(self):
        self.engine.clear_params()
        self.refresh(force=True)

    def refresh(self, force=False):
        params = self.engine.get_params()
        snap = tuple((p["key"], p["value"], p["count"]) for p in params)
        if not force and snap == self._snapshot:
            return
        self._snapshot = snap
        self.count_label.setText(f"{len(params)} 项")
        alive = set()
        for p in params:
            alive.add(p["key"])
            row = self._rows.get(p["key"])
            if row is None:
                row = self._make_row()
                self._rows[p["key"]] = row
                self.rows_layout.addWidget(row)
            self._fill_row(row, p)
        for key in list(self._rows):
            if key not in alive:
                row = self._rows.pop(key)
                self.rows_layout.removeWidget(row)
                row.deleteLater()

    def _make_row(self):
        row = QFrame()
        row.setObjectName("paramRow")
        layout = QVBoxLayout(row)
        layout.setContentsMargins(10, 7, 10, 7)
        layout.setSpacing(2)
        top = QHBoxLayout()
        name = QLabel()
        name.setObjectName("paramName")
        value = QLabel()
        value.setObjectName("paramValue")
        top.addWidget(name, 1)
        top.addWidget(value)
        meta = QLabel()
        meta.setObjectName("paramMeta")
        layout.addLayout(top)
        layout.addWidget(meta)
        row._name = name
        row._value = value
        row._meta = meta
        return row

    def _fill_row(self, row, p):
        row._name.setText(p["name"])
        row._value.setText(f"{p['value']:,.6g}{p.get('unit', '')}")
        row._meta.setText(f"raw {p['raw']} · 更新 {p['count']} 次 · "
                          f"{fmt_ts(p['ts'])}")


# ------------------------------------------------------------ connection --
class ConnectionPanel(QFrame):
    def __init__(self, engine, toast, parent=None):
        super().__init__(parent)
        self.engine = engine
        self.toast = toast
        self.setObjectName("card")
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 14)
        root.setSpacing(10)
        head = QHBoxLayout()
        title = QLabel("串口连接")
        title.setObjectName("cardTitle")
        head.addWidget(title)
        head.addStretch(1)
        refresh = QPushButton("刷新")
        refresh.setObjectName("ghost")
        refresh.setFixedHeight(26)
        refresh.clicked.connect(self.refresh_ports)
        head.addWidget(refresh)
        root.addLayout(head)

        grid = QGridLayout()
        grid.setSpacing(8)
        grid.setVerticalSpacing(10)
        self.port = QComboBox()
        self.baud = QComboBox()
        self.baud.setEditable(True)
        for rate in (9600, 57600, 115200, 230400, 460800, 921600,
                     1000000, 5000000):
            self.baud.addItem(str(rate))
        self.data_bits = QComboBox()
        self.data_bits.addItems(["8", "7", "6", "5"])
        self.parity = QComboBox()
        for value, text in (("none", "无校验"), ("even", "偶校验"),
                            ("odd", "奇校验"), ("mark", "Mark"),
                            ("space", "Space")):
            self.parity.addItem(text, value)
        self.stop_bits = QComboBox()
        for value in ("1", "1.5", "2"):
            self.stop_bits.addItem(value, value)
        self.encoding = QComboBox()
        for enc in ENCODINGS:
            self.encoding.addItem(enc.upper(), enc)
        self.encoding.currentIndexChanged.connect(self._encoding_changed)

        fields = [("串口", self.port, 0, 0, 1, 2), ("波特率", self.baud, 1, 0, 1, 2),
                  ("数据位", self.data_bits, 2, 0), ("停止位", self.stop_bits, 2, 1),
                  ("校验", self.parity, 3, 0, 1, 2),
                  ("编码", self.encoding, 4, 0, 1, 2)]
        for spec in fields:
            label_text, widget, r, c = spec[0], spec[1], spec[2], spec[3]
            rs = spec[4] if len(spec) > 4 else 1
            cs = spec[5] if len(spec) > 5 else 1
            cell = QVBoxLayout()
            label = QLabel(label_text)
            label.setObjectName("fieldLabel")
            cell.addWidget(label)
            cell.addWidget(widget)
            grid.addLayout(cell, r, c, rs, cs)
        root.addLayout(grid)

        modem = QHBoxLayout()
        modem.setSpacing(8)
        self.dtr_btn = QPushButton("DTR")
        self.dtr_btn.setObjectName("miniToggle")
        self.dtr_btn.setCheckable(True)
        self.dtr_btn.setToolTip("DTR 流控信号（部分板卡用作复位）")
        self.dtr_btn.clicked.connect(self._modem_changed)
        self.rts_btn = QPushButton("RTS")
        self.rts_btn.setObjectName("miniToggle")
        self.rts_btn.setCheckable(True)
        self.rts_btn.setToolTip("RTS 流控信号")
        self.rts_btn.clicked.connect(self._modem_changed)
        modem.addWidget(self.dtr_btn)
        modem.addWidget(self.rts_btn)
        modem.addStretch(1)
        root.addLayout(modem)

        self.connect_btn = QPushButton("连 接")
        self.connect_btn.setObjectName("primary")
        self.connect_btn.setFixedHeight(36)
        self.connect_btn.clicked.connect(self._toggle)
        root.addWidget(self.connect_btn)
        root.addStretch(1)

        self.refresh_ports()
        cfg = self.engine.config
        if cfg.get("baud"):
            self.baud.setCurrentText(str(cfg["baud"]))
        idx = self.parity.findData(cfg.get("parity", "none"))
        if idx >= 0:
            self.parity.setCurrentIndex(idx)
        idx = self.stop_bits.findData(cfg.get("stopBits", "1"))
        if idx >= 0:
            self.stop_bits.setCurrentIndex(idx)
        idx = self.data_bits.findText(str(cfg.get("dataBits", 8)))
        if idx >= 0:
            self.data_bits.setCurrentIndex(idx)
        idx = self.encoding.findData(cfg.get("encoding", "utf-8"))
        if idx >= 0:
            self.encoding.setCurrentIndex(idx)
        self.dtr_btn.setChecked(bool(cfg.get("dtr")))
        self.rts_btn.setChecked(bool(cfg.get("rts")))

    def refresh_ports(self):
        current = self.port.currentData() or self.engine.config.get("port", "")
        self.port.clear()
        for p in self.engine.ports():
            self.port.addItem(f"{p['device']}  ·  {p['description']}",
                              p["device"])
        idx = self.port.findData(current)
        self.port.setCurrentIndex(idx if idx >= 0 else 0)

    def _encoding_changed(self):
        try:
            self.engine.set_encoding(self.encoding.currentData())
        except ValueError as exc:
            self.toast.show_message(str(exc), error=True)

    def _modem_changed(self):
        self.engine.set_modem(dtr=self.dtr_btn.isChecked(),
                              rts=self.rts_btn.isChecked())

    def _toggle(self):
        if self.engine.status()["connected"]:
            self.engine.disconnect()
            return
        if self.port.currentData() is None:
            self.toast.show_message("没有可用的串口", error=True)
            return
        try:
            baud = int(self.baud.currentText())
        except ValueError:
            self.toast.show_message("波特率必须是数字", error=True)
            return
        try:
            self.engine.connect(
                port=self.port.currentData(), baud=baud,
                data_bits=int(self.data_bits.currentText()),
                parity=self.parity.currentData(),
                stop_bits=self.stop_bits.currentData(),
                dtr=self.dtr_btn.isChecked(),
                rts=self.rts_btn.isChecked())
        except Exception as exc:
            self.toast.show_message(f"连接失败：{exc}", error=True)

    def sync_status(self, st):
        connected = st["connected"]
        for w in (self.port, self.baud, self.data_bits, self.parity,
                  self.stop_bits):
            w.setEnabled(not connected)
        self.connect_btn.setText("断 开" if connected else "连 接")
        enc = st.get("encoding", "utf-8")
        if self.encoding.currentData() != enc:
            self.encoding.blockSignals(True)
            idx = self.encoding.findData(enc)
            if idx >= 0:
                self.encoding.setCurrentIndex(idx)
            self.encoding.blockSignals(False)
        if self.dtr_btn.isChecked() != bool(st.get("dtr")):
            self.dtr_btn.blockSignals(True)
            self.dtr_btn.setChecked(bool(st.get("dtr")))
            self.dtr_btn.blockSignals(False)
        if self.rts_btn.isChecked() != bool(st.get("rts")):
            self.rts_btn.blockSignals(True)
            self.rts_btn.setChecked(bool(st.get("rts")))
            self.rts_btn.blockSignals(False)


# ------------------------------------------------------------ main window --
class MainWindow(QMainWindow):
    def __init__(self, engine):
        super().__init__()
        self.engine = engine
        self.setWindowTitle("EdRV32 调试工具")
        self.resize(1360, 860)
        self.setMinimumSize(1080, 680)
        self.setStyleSheet(QSS)
        # Never trust the shell's default placement: with phantom
        # (disconnected) monitors it can be off-screen. Center explicitly.
        screen = QGuiApplication.primaryScreen()
        if screen is not None:
            area = screen.availableGeometry()
            self.move(area.x() + max(0, (area.width() - self.width()) // 2),
                      area.y() + max(0, (area.height() - self.height()) // 2))

        root = QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)
        root_layout = QVBoxLayout(root)
        root_layout.setContentsMargins(0, 0, 0, 0)
        root_layout.setSpacing(0)

        # ---- header ----
        header = QWidget()
        header.setObjectName("header")
        header.setFixedHeight(64)
        h = QHBoxLayout(header)
        h.setContentsMargins(18, 0, 18, 0)
        logo = QLabel("E2")
        logo.setObjectName("logo")
        logo.setAlignment(Qt.AlignCenter)
        h.addWidget(logo)
        title_box = QVBoxLayout()
        title_box.setSpacing(1)
        title = QLabel(
            'EdRV32 <span style="color:#8b98a9; font-weight:400">'
            '调试工具</span>')
        title.setObjectName("appTitle")
        sub = QLabel("PG2L200H · UART / ETH · REST API READY")
        sub.setObjectName("appSub")
        title_box.addWidget(title)
        title_box.addWidget(sub)
        h.addLayout(title_box)
        h.addStretch(1)
        self.chip = QWidget()
        self.chip.setObjectName("chip")
        self.chip.setFixedHeight(30)
        chip_layout = QHBoxLayout(self.chip)
        chip_layout.setContentsMargins(10, 0, 10, 0)
        chip_layout.setSpacing(8)
        self.chip_dot = QLabel()
        self.chip_dot.setObjectName("chipDot")
        self.chip_text = QLabel("未连接")
        self.chip_text.setObjectName("chipText")
        chip_layout.addWidget(self.chip_dot)
        chip_layout.addWidget(self.chip_text)
        h.addWidget(self.chip)
        root_layout.addWidget(header)

        # ---- body ----
        body = QHBoxLayout()
        body.setContentsMargins(14, 12, 14, 10)
        body.setSpacing(0)
        root_layout.addLayout(body, 1)

        self.toast = Toast(self)

        # left: icon rail + stacked panels (连接 / 命令 / 规则)
        left_container = QWidget()
        left_container.setMinimumWidth(300)
        left_layout = QHBoxLayout(left_container)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(8)
        rail = QFrame()
        rail.setObjectName("rail")
        rail.setFixedWidth(66)
        rail_layout = QVBoxLayout(rail)
        rail_layout.setContentsMargins(6, 10, 6, 10)
        rail_layout.setSpacing(6)
        self.rail_group = QButtonGroup(self)
        self.left_stack = QStackedWidget()
        for i, (label, tip, paths) in enumerate((
                ("连接", "串口连接与参数", ICON_PLUG),
                ("命令", "快捷命令按钮", ICON_TERMINAL),
                ("规则", "数据匹配规则", ICON_FILTER),
                ("网口", "UDP 文件收发", ICON_NETWORK),
                ("调试", "烧录、图像与检测", ICON_DASHBOARD))):
            btn = QToolButton()
            btn.setObjectName("railBtn")
            btn.setCheckable(True)
            btn.setToolTip(tip)
            btn.setIcon(state_icon(paths))
            btn.setIconSize(QSize(20, 20))
            btn.setText(label)
            btn.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
            self.rail_group.addButton(btn, i)
            rail_layout.addWidget(btn)
        rail_layout.addStretch(1)
        self.rail_group.idClicked.connect(self._select_page)
        self.rail_group.button(0).setChecked(True)

        self.conn = ConnectionPanel(engine, self.toast)
        self.cmds = CommandsPanel(engine, self.toast)
        self.rules = RulesPanel(engine, self.toast)
        self.left_stack.addWidget(self.conn)
        self.left_stack.addWidget(self.cmds)
        self.left_stack.addWidget(self.rules)
        self.ethernet = EthernetPanel(engine.ethernet, self.toast)
        ethernet_scroll = QScrollArea()
        ethernet_scroll.setWidgetResizable(True)
        ethernet_scroll.setFrameShape(QFrame.NoFrame)
        ethernet_scroll.setWidget(self.ethernet)
        self.left_stack.addWidget(ethernet_scroll)
        left_layout.addWidget(self.left_stack, 1)

        # center: console
        console_card = QFrame()
        console_card.setObjectName("card")
        console_card.setMinimumWidth(380)
        cc = QVBoxLayout(console_card)
        cc.setContentsMargins(14, 12, 14, 12)
        cc.setSpacing(10)
        head = QHBoxLayout()
        title = QLabel("串口控制台")
        title.setObjectName("cardTitle")
        head.addWidget(title)
        head.addStretch(1)

        self.mode_combo = QComboBox()
        self.mode_combo.setObjectName("mini")
        self.mode_combo.addItem("文本显示", "text")
        self.mode_combo.addItem("HEX 显示", "hex")
        self.mode_combo.setFixedWidth(96)
        self.mode_combo.setToolTip("控制台显示模式：文本 / 十六进制（作用于已有内容）")
        head.addWidget(self.mode_combo)
        ts_btn = QPushButton("时间戳")
        ts_btn.setObjectName("miniToggle")
        ts_btn.setCheckable(True)
        ts_btn.setChecked(True)
        head.addWidget(ts_btn)
        self.dir_btns = {}
        for d, label in (("rx", "RX"), ("tx", "TX"), ("sys", "SYS")):
            btn = QPushButton(label)
            btn.setObjectName("miniToggle")
            btn.setCheckable(True)
            btn.setChecked(True)
            btn.setToolTip(f"显示 / 隐藏 {label}")
            self.dir_btns[d] = btn
            head.addWidget(btn)
        save_btn = QPushButton("保 存")
        save_btn.setObjectName("ghost")
        save_btn.setToolTip("将缓冲区写入 tools/debug_tool/logs/")
        save_btn.clicked.connect(self._save)
        clear_btn = QPushButton("清 空")
        clear_btn.setObjectName("ghostDanger")
        clear_btn.clicked.connect(self._clear)
        head.addWidget(save_btn)
        head.addWidget(clear_btn)
        cc.addLayout(head)

        self.console = ConsoleView()
        cc.addWidget(self.console, 1)

        # file-transfer progress row (hidden unless a transfer is running)
        self.file_row = QWidget()
        file_layout = QHBoxLayout(self.file_row)
        file_layout.setContentsMargins(0, 0, 0, 0)
        file_layout.setSpacing(8)
        self.file_bar = QProgressBar()
        self.file_bar.setTextVisible(False)
        self.file_label = QLabel("")
        self.file_label.setObjectName("fileLabel")
        file_cancel = QPushButton("取消")
        file_cancel.setObjectName("miniToggle")
        file_cancel.clicked.connect(self.engine.cancel_file)
        file_layout.addWidget(self.file_bar, 1)
        file_layout.addWidget(self.file_label)
        file_layout.addWidget(file_cancel)
        self.file_row.hide()
        cc.addWidget(self.file_row)

        self.mode_combo.currentIndexChanged.connect(
            lambda _: self.console.set_mode(self.mode_combo.currentData()))
        ts_btn.toggled.connect(self.console.set_timestamps)
        for d, btn in self.dir_btns.items():
            btn.toggled.connect(
                lambda on, dd=d: self.console.set_dir_visible(dd, on))

        composer = QHBoxLayout()
        composer.setSpacing(8)
        self.tx_input = QLineEdit()
        self.tx_input.setPlaceholderText("输入要发送的内容，Enter 发送…")
        self.tx_input.returnPressed.connect(self._send)
        self.hex_toggle = QPushButton("HEX发")
        self.hex_toggle.setObjectName("miniToggle")
        self.hex_toggle.setCheckable(True)
        self.hex_toggle.setToolTip(
            "HEX 发送：把输入框内容按十六进制发出，例如: 01 03 FF\n"
            "（只影响发送；想以十六进制查看数据请用右上「HEX 显示」）")
        self.file_btn = QPushButton("文 件")
        self.file_btn.setObjectName("ghost")
        self.file_btn.setToolTip("选择文件并通过串口发送（原始字节，分块传输）")
        self.file_btn.clicked.connect(self._send_file)
        self.echo_toggle = QPushButton("回显")
        self.echo_toggle.setObjectName("miniToggle")
        self.echo_toggle.setCheckable(True)
        self.echo_toggle.setToolTip("开启后，文件内容也会以 TX 条目打印到控制台")
        self.tx_ending = QComboBox()
        for value, text in (("cr", r"＋\r"), ("lf", r"＋\n"),
                            ("crlf", r"＋\r\n"), ("none", "无行尾")):
            self.tx_ending.addItem(text, value)
        self.tx_ending.setFixedWidth(92)
        self.send_btn = QPushButton("发 送")
        self.send_btn.setObjectName("primary")
        self.send_btn.setFixedWidth(86)
        self.send_btn.clicked.connect(self._send)
        composer.addWidget(self.tx_input, 1)
        composer.addWidget(self.hex_toggle)
        composer.addWidget(self.file_btn)
        composer.addWidget(self.echo_toggle)
        composer.addWidget(self.tx_ending)
        composer.addWidget(self.send_btn)
        cc.addLayout(composer)

        # right: live parameters
        self.data_panel = DataPanel(engine, self.toast)
        self.data_panel.setMinimumWidth(240)

        main_split = QSplitter(Qt.Horizontal)
        main_split.addWidget(left_container)
        main_split.addWidget(console_card)
        main_split.addWidget(self.data_panel)
        main_split.setChildrenCollapsible(False)
        main_split.setStretchFactor(0, 0)
        main_split.setStretchFactor(1, 1)
        main_split.setStretchFactor(2, 0)
        main_split.setSizes([330, 680, 300])
        self.main_split = main_split
        self.console_card = console_card
        self.body_stack = QStackedWidget()
        self.body_stack.addWidget(main_split)
        self.soc = SocConsole(engine, self.toast)
        self.body_stack.addWidget(self.soc)
        body.addWidget(rail)
        body.addSpacing(8)
        body.addWidget(self.body_stack, 1)

        # ---- footer ----
        footer = QWidget()
        footer.setObjectName("footer")
        footer.setFixedHeight(28)
        f = QHBoxLayout(footer)
        f.setContentsMargins(18, 0, 18, 0)
        self.counters = QLabel("RX 0 B / TX 0 B")
        self.counters.setObjectName("footText")
        right = QLabel("RV32IM · clk_sys 100 MHz · clk_mem 125 MHz")
        right.setObjectName("footText")
        f.addWidget(self.counters)
        f.addStretch(1)
        f.addWidget(right)
        root_layout.addWidget(footer)

        # ---- engine wiring ----
        # The RX thread only queues into a plain list; a 50 ms GUI timer
        # renders each batch in one shot so fast streams can't stall the UI.
        self.entry_batch = EngineBatch()
        engine.add_listener(self.entry_batch.push)
        self.console.append_many(engine.get_entries()[0][-200:])

        self.flush_timer = QTimer(self)
        self.flush_timer.timeout.connect(self._flush_entries)
        self.flush_timer.start(50)
        self.status_timer = QTimer(self)
        self.status_timer.timeout.connect(self._poll_status)
        self.status_timer.start(500)
        self.param_timer = QTimer(self)
        self.param_timer.timeout.connect(self.data_panel.refresh)
        self.param_timer.start(400)
        self.cmd_timer = QTimer(self)
        self.cmd_timer.timeout.connect(self._reload_panels)
        self.cmd_timer.start(1500)
        for field in self.findChildren(QLineEdit):
            field.setToolTip(field.text() or field.placeholderText())
            field.textChanged.connect(lambda text, field=field: field.setToolTip(text))
        self._poll_status()
        self.data_panel.refresh(force=True)
        self.rail_group.button(4).setChecked(True)
        self._select_page(4)

    # -- actions ----------------------------------------------------------
    def _send(self):
        text = self.tx_input.text()
        if not text:
            return
        try:
            self.engine.send(text, self.tx_ending.currentData(),
                             hex_mode=self.hex_toggle.isChecked())
            self.tx_input.clear()
        except ValueError as exc:
            self.toast.show_message(str(exc), error=True)
        except RuntimeError:
            self.toast.show_message("串口未连接", error=True)

    def _send_file(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择要发送的文件")
        if not path:
            return
        try:
            self.engine.send_file(path, echo=self.echo_toggle.isChecked())
        except (ValueError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)

    def _update_file_row(self):
        st = self.engine.file_status()
        if st.get("active"):
            total = max(1, st.get("total", 1))
            sent = st.get("sent", 0)
            self.file_bar.setMaximum(total)
            self.file_bar.setValue(sent)
            self.file_label.setText(
                f"{st.get('name','')}  {fmt_bytes(sent)}/"
                f"{fmt_bytes(total)} ({100.0*sent/total:.0f}%)")
            self.file_row.show()
        else:
            self.file_row.hide()

    def _save(self):
        try:
            result = self.engine.save_log()
            self.toast.show_message(f"已保存:{result['path']}")
        except OSError as exc:
            self.toast.show_message(f"保存失败:{exc}", error=True)

    def _clear(self):
        self.engine.clear()

    def _flush_entries(self):
        # at most ~400 lines per 50 ms tick -> up to 8000 lines/s displayed,
        # far beyond what any UART can deliver, and each repaint stays small
        entries = self.entry_batch.drain(limit=400)
        if not entries:
            return
        lines = []
        for entry in entries:
            if entry.get("dir") == "cleared":
                self.console.clear()
            else:
                lines.append(entry)
        self.console.append_many(lines)

    def _select_page(self, index):
        console = index == 4
        self.body_stack.setCurrentIndex(1 if console else 0)
        if not console:
            self.left_stack.setCurrentIndex(index)
            self.main_split.setSizes([300, 680, 300])
        else:
            self.soc.refresh()

    def _poll_status(self):
        st = self.engine.status()
        connected = st["connected"]
        cfg = st["config"]
        self.chip_dot.setStyleSheet(
            f"background:{'#22c55e' if connected else '#e05c6a'};"
            "border-radius:5px;")
        self.chip_text.setText(
            f"{cfg['port']} @ {cfg['baud']}" if connected else "未连接")
        self.conn.sync_status(st)
        self.send_btn.setEnabled(connected)
        self.tx_input.setEnabled(connected)
        self.file_btn.setEnabled(connected)
        self._update_file_row()
        self.ethernet.refresh()
        self.soc.refresh()
        self.counters.setText(
            f"RX {fmt_bytes(st['rxBytes'])} / TX {fmt_bytes(st['txBytes'])}")

    def _reload_panels(self):
        self.cmds.reload()
        self.rules.reload()

    def closeEvent(self, event):
        self.engine.ethernet.stop_receive()
        self.engine.disconnect(silent=True)
        super().closeEvent(event)
