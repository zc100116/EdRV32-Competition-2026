"""games.py — showcase design 4.4 / 4.5.5 game upload page; Qt main thread."""
from pathlib import Path

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (QFileDialog, QFormLayout, QHBoxLayout, QLabel, QLineEdit,
                               QProgressBar, QPushButton, QVBoxLayout, QWidget)

from tools.sw.game_record import build_record


class GamesPanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine, self.toast = engine, toast
        self.error = None
        layout = QVBoxLayout(self)
        layout.setContentsMargins(32, 18, 32, 18)
        title = QLabel('游戏')
        title.setStyleSheet('font-size:22px;font-weight:700;color:#263e62;')
        layout.addWidget(title)
        note = QLabel('选择游戏和可选封面，上传后追加到板端游戏列表。上传的游戏在复位或断电后清空。')
        note.setWordWrap(True)
        layout.addWidget(note)
        form = QFormLayout()
        self.ip = QLineEdit(engine.board.network_endpoint[0])
        self.local_ip = QLineEdit(engine.ethernet.local_ip)
        form.addRow('设备地址', self.ip)
        form.addRow('本机地址', self.local_ip)
        self.rom = QLineEdit()
        self.cover = QLineEdit()
        self.name = QLineEdit()
        self.name.setPlaceholderText('默认使用 ROM 文件名，可修改')
        for title, field, callback in (('ROM 文件', self.rom, self.choose_rom),
                                        ('封面（可选）', self.cover, self.choose_cover)):
            row = QHBoxLayout()
            row.addWidget(field, 1)
            choose = QPushButton('选择文件')
            choose.clicked.connect(callback)
            row.addWidget(choose)
            form.addRow(title, row)
            field.textChanged.connect(field.setToolTip)
        form.addRow('游戏名称', self.name)
        self.name.textChanged.connect(self.name.setToolTip)
        layout.addLayout(form)
        hint = QLabel('封面支持 PNG / JPG，等比缩放、居中留白。游戏名完整显示，长名字自动换行。')
        hint.setWordWrap(True)
        layout.addWidget(hint)
        self.upload = QPushButton('上传游戏')
        self.upload.clicked.connect(self.send)
        layout.addWidget(self.upload)
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        layout.addWidget(self.progress)
        self.result = QLabel('尚未上传')
        self.result.setWordWrap(True)
        layout.addWidget(self.result)
        layout.addStretch()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(200)

    def choose_rom(self):
        path, _ = QFileDialog.getOpenFileName(self, '选择游戏 ROM', '', 'NES 游戏 (*.nes)')
        if path:
            self.rom.setText(path)
            self.name.setText(Path(path).stem)

    def choose_cover(self):
        path, _ = QFileDialog.getOpenFileName(self, '选择封面', '', '封面图片 (*.png *.jpg *.jpeg)')
        if path:
            self.cover.setText(path)

    def send(self):
        self.error = None
        try:
            path = Path(self.rom.text())
            name = self.name.text() or path.stem
            self.name.setText(name)
            record = build_record(name, path.read_bytes(),
                                  Path(self.cover.text()) if self.cover.text() else None)
            self.engine.ethernet.local_ip = self.local_ip.text()
            self.engine.ethernet.listen_console(6000)
            self.engine.ethernet.showcase.bulk(3, record, self.ip.text(), 5000, 6000,
                                               f'游戏 · {name}')
        except (OSError, ValueError, RuntimeError) as exc:
            self.error = str(exc)
            self.result.setText(self.error)
            self.engine.board.fail(str(exc))
            self.toast.show_message(str(exc), error=True)
        else:
            self.refresh()

    def refresh(self):
        tx = self.engine.ethernet.status()['tx']
        self.upload.setEnabled(not tx['active'])
        if self.error is not None:
            self.result.setText(self.error)
            return
        if not tx.get('path', '').startswith('游戏 · '):
            return
        self.progress.setValue(int(100 * tx['sent'] / tx['total']) if tx['total'] else 0)
        text = f"{tx['path']} · {tx['sent']:,} / {tx['total']:,} B\n"
        if tx['error']:
            text += f"上传失败：{tx['error']}"
        elif tx['active']:
            text += tx['phase']
        else:
            text += f"上传完成 · 板端序号 {tx['index']}，可继续上传下一个游戏"
        self.result.setText(text)
