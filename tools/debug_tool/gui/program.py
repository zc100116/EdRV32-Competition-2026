"""program.py — BIOS programming panel, SoC spec 7.5(3a); host, no clock domain."""

from PySide6.QtWidgets import (
    QFileDialog, QFrame, QLabel, QLineEdit, QProgressBar, QPushButton, QVBoxLayout,
)


class ProgramPanel(QFrame):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine = engine
        self.toast = toast
        self.setObjectName("card")
        layout = QVBoxLayout(self)
        title = QLabel("BIOS · 烧录 SRAM")
        title.setObjectName("cardTitle")
        layout.addWidget(title)
        hint = QLabel("选择 make 生成的 .bin，点击烧录，\n然后按住 KEY1 按复位。")
        hint.setWordWrap(True)
        layout.addWidget(hint)
        self.path = QLineEdit()
        self.path.setPlaceholderText("build/sw/<程序>/<程序>.bin")
        layout.addWidget(self.path)
        choose = QPushButton("选择 .bin 文件")
        choose.clicked.connect(self._choose)
        layout.addWidget(choose)
        self.start = QPushButton("烧录 SRAM")
        self.start.clicked.connect(self._start)
        layout.addWidget(self.start)
        self.progress = QProgressBar()
        layout.addWidget(self.progress)
        self.result = QLabel("等待选择文件")
        self.result.setWordWrap(True)
        layout.addWidget(self.result)
        layout.addStretch(1)

    def _choose(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择 SRAM 镜像", "", "Binary (*.bin)")
        if path:
            self.path.setText(path)

    def _start(self):
        try:
            self.engine.start_program(self.path.text())
            self.refresh()
        except (OSError, ValueError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)

    def refresh(self):
        state = self.engine.program.status()
        self.start.setEnabled(self.engine.status()["connected"] and not state["active"])
        self.progress.setMaximum(max(1, state["total"]))
        self.progress.setValue(state["sent"])
        phases = {"idle": "等待选择文件", "wait_menu": "按住 KEY1 按复位；等待 BIOS menu",
                  "wait_ready": "已发送 1 + CR；等待 UART download ready",
                  "sending": "正在发送镜像", "wait_result": "等待 Program SRAM result",
                  "done": state["result"], "error": state["error"]}
        text = phases[state["phase"]]
        if state["programmedBytes"] is not None:
            text += f"\nProgram SRAM bytes: {state['programmedBytes']}"
        self.result.setText(text)
