"""program.py — BIOS programming panel, SoC spec 7.5(3a); host, no clock domain."""

from PySide6.QtWidgets import (
    QComboBox, QFileDialog, QFrame, QLabel, QLineEdit, QProgressBar, QPushButton, QVBoxLayout,
)


class ProgramPanel(QFrame):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine = engine
        self.toast = toast
        self.setObjectName("card")
        layout = QVBoxLayout(self)
        title = QLabel("BIOS · 烧录 / 加载运行")
        title.setObjectName("cardTitle")
        layout.addWidget(title)
        hint = QLabel("以 115200 连接串口，选择镜像并开始。\n"
                      "已在 BIOS 菜单时直接开始；否则按住 KEY1 并复位。ELF 加载后立即运行。")
        hint.setWordWrap(True)
        layout.addWidget(hint)
        self.mode = QComboBox()
        self.mode.addItem("烧录 SRAM（.bin，复位后运行）", False)
        self.mode.addItem("加载 ELF 并运行（SRAM / DDR）", True)
        self.mode.currentIndexChanged.connect(self._mode_changed)
        layout.addWidget(self.mode)
        self.baud = QComboBox()
        for value in (2000000, 921600, 115200):
            self.baud.addItem(f"{value}" + ("（不切换）" if value == 115200 else ""), value)
        self.baud.setEnabled(False)
        layout.addWidget(QLabel("ELF 加载波特率"))
        layout.addWidget(self.baud)
        self.path = QLineEdit()
        self.path.setPlaceholderText("build/sw/<程序>/<程序>.bin")
        layout.addWidget(self.path)
        self.choose = QPushButton("选择 .bin 文件")
        self.choose.clicked.connect(self._choose)
        layout.addWidget(self.choose)
        self.start = QPushButton("烧录 SRAM")
        self.start.clicked.connect(self._start)
        layout.addWidget(self.start)
        self.progress = QProgressBar()
        layout.addWidget(self.progress)
        self.result = QLabel("等待选择文件")
        self.result.setWordWrap(True)
        layout.addWidget(self.result)
        layout.addStretch(1)

    def _mode_changed(self):
        elf = self.mode.currentData()
        self.baud.setEnabled(elf)
        self.choose.setText("选择 .elf 文件" if elf else "选择 .bin 文件")
        self.start.setText("加载 ELF 并运行" if elf else "烧录 SRAM")
        self.path.setPlaceholderText("build/sw/<程序>/<程序>." + ("elf" if elf else "bin"))

    def _choose(self):
        elf = self.mode.currentData()
        path, _ = QFileDialog.getOpenFileName(self, "选择程序镜像", "",
                                              "ELF (*.elf)" if elf else "Binary (*.bin)")
        if path:
            self.path.setText(path)

    def _start(self):
        try:
            self.engine.start_program(self.path.text(), self.mode.currentData(),
                                      self.baud.currentData())
            self.refresh()
        except (OSError, ValueError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)

    def refresh(self):
        state = self.engine.program.status()
        self.start.setEnabled(self.engine.status()["connected"] and not state["active"])
        self.progress.setMaximum(max(1, state["total"]))
        self.progress.setValue(state["sent"])
        phases = {"idle": "等待选择文件",
                  "wait_menu": "已在 BIOS 菜单时直接开始；否则按住 KEY1 并复位",
                  "wait_ready": "已发送菜单选择；等待 BIOS 提示",
                  "wait_result": "正在传输 / 等待 BIOS 结果",
                  "done": state["result"], "error": state["error"]}
        text = phases[state["phase"]]
        if state["programmedBytes"] is not None:
            text += f"\n已写入: {state['programmedBytes']} 字节"
        self.result.setText(text)
