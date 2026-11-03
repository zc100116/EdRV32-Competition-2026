"""ethernet.py — eth spec 2.1–2.6 UDP file panel; host, no clock domain."""

from PySide6.QtWidgets import (
    QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout, QFrame, QLabel, QLineEdit,
    QProgressBar, QPushButton, QSpinBox, QVBoxLayout,
)
import struct

from core.ethernet import DEFAULT_SAVE_DIR


class EthernetPanel(QFrame):
    def __init__(self, ethernet, toast):
        super().__init__()
        self.ethernet = ethernet
        self.toast = toast
        self.setObjectName("card")
        layout = QVBoxLayout(self)
        title = QLabel("ETH · UDP 文件收发")
        title.setObjectName("cardTitle")
        layout.addWidget(title)
        form = QFormLayout()
        self.ip = QLineEdit("192.168.1.10")
        form.addRow("板子 IP", self.ip)
        self.board_port = QSpinBox()
        self.board_port.setRange(1, 65535)
        self.board_port.setValue(5000)
        form.addRow("板子 RX_PORT", self.board_port)
        self.local_ip = QLineEdit(ethernet.local_ip)
        form.addRow("本机地址", self.local_ip)
        self.local_port = QSpinBox()
        self.local_port.setRange(1, 65535)
        self.local_port.setValue(6000)
        form.addRow("PC 本地端口", self.local_port)
        layout.addLayout(form)
        self.path = QLineEdit()
        self.path.setPlaceholderText("待发送文件")
        layout.addWidget(self.path)
        choose = QPushButton("选择发送文件")
        choose.clicked.connect(self._choose_send)
        layout.addWidget(choose)
        fields = QFormLayout()
        self.window = QComboBox()
        self.window.addItems(["大块数据", "未使用", "虚拟输入", "控制与监控"])
        fields.addRow("数据用途", self.window)
        self.offset = QLineEdit("0")
        self.offset.setPlaceholderText("十进制或 0x 十六进制")
        fields.addRow("起始偏移", self.offset)
        self.interval = QDoubleSpinBox()
        self.interval.setRange(0, 60000)
        self.interval.setDecimals(3)
        self.interval.setSuffix(" ms")
        fields.addRow("包间隔", self.interval)
        layout.addLayout(fields)
        self.send = QPushButton("发送文件")
        self.send.clicked.connect(self._send)
        layout.addWidget(self.send)
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        layout.addWidget(self.progress)
        self.tx_status = QLabel("尚未发送")
        self.tx_status.setWordWrap(True)
        layout.addWidget(self.tx_status)
        self.directory = QLineEdit(str(DEFAULT_SAVE_DIR))
        layout.addWidget(self.directory)
        choose_rx = QPushButton("选择接收保存目录")
        choose_rx.clicked.connect(self._choose_receive)
        layout.addWidget(choose_rx)
        hint = QLabel("按数据用途保存到所选目录，\n"
                      "按 OFFSET 写入；每次监听首次收到该用途数据时覆盖旧文件。")
        hint.setWordWrap(True)
        layout.addWidget(hint)
        self.listen = QPushButton("开始监听")
        self.listen.clicked.connect(self._listen)
        layout.addWidget(self.listen)
        self.rx_status = QLabel("未监听")
        self.rx_status.setWordWrap(True)
        layout.addWidget(self.rx_status)
        layout.addWidget(QLabel('网口回环测试'))
        self.echo_count = QSpinBox()
        self.echo_count.setRange(1, 2147483647)
        self.echo_count.setValue(10)
        echo_form = QFormLayout()
        echo_form.addRow('测试次数', self.echo_count)
        layout.addLayout(echo_form)
        self.echo_button = QPushButton('开始回环测试')
        self.echo_button.clicked.connect(self._echo)
        layout.addWidget(self.echo_button)
        self.echo_result = QLabel('尚未测试')
        self.echo_result.setWordWrap(True)
        layout.addWidget(self.echo_result)
        layout.addStretch(1)

    def _choose_send(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择 UDP 发送文件")
        if path:
            self.path.setText(path)

    def _choose_receive(self):
        path = QFileDialog.getExistingDirectory(self, "接收保存目录", self.directory.text())
        if path:
            self.directory.setText(path)

    def _send(self):
        try:
            self.ethernet.local_ip = self.local_ip.text()
            self.ethernet.send_file(
                self.path.text(), self.ip.text(), self.board_port.value(),
                self.local_port.value(), self.window.currentIndex(),
                int(self.offset.text(), 0), self.interval.value() / 1000)
        except (OSError, ValueError, RuntimeError, struct.error) as exc:
            self.toast.show_message(str(exc), error=True)
        self.refresh()

    def _echo(self):
        try:
            self.ethernet.local_ip = self.local_ip.text()
            self.ethernet.showcase.echo_test(self.echo_count.value(), self.ip.text(),
                                             self.board_port.value(), self.local_port.value())
        except (OSError, ValueError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)
            if self.ethernet.session:
                self.ethernet.session.fail(str(exc))
        self.refresh()

    def _listen(self):
        try:
            if self.ethernet.status()["rx"]["active"]:
                self.ethernet.stop_receive()
            else:
                self.ethernet.local_ip = self.local_ip.text()
                self.ethernet.start_receive(self.local_port.value(), self.directory.text())
        except (OSError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)
        self.refresh()

    def refresh(self):
        state = self.ethernet.status()
        tx, rx = state["tx"], state["rx"]
        self.send.setEnabled(not tx["active"])
        self.echo_button.setEnabled(not tx['active'])
        echo = state['echo']
        average = '—' if echo['averageMs'] is None else f"{echo['averageMs']:.3f} ms"
        self.echo_result.setText(f"次数 {echo['count']} · 已返回 {echo['received']} · "
                                 f"丢失 {echo['lost']}\n平均往返 {average}")
        self.local_ip.setEnabled(not (tx["active"] or rx["active"]))
        self.local_port.setEnabled(not (tx["active"] or rx["active"]))
        self.directory.setEnabled(not rx["active"])
        self.progress.setValue(int(100 * tx["sent"] / tx["total"]) if tx["total"] else 0)
        self.tx_status.setText(
            f"{'发送中' if tx['active'] else '发送'}: {tx['sent']}/{tx['total']} B，"
            f"{tx['packets']} 包" + (f"\n错误: {tx['error']}" if tx["error"] else ""))
        self.listen.setText("停止监听" if rx["active"] else "开始监听")
        text = (f"{'监听中' if rx['active'] else '已停止'}: {rx['packets']} 包，"
                f"{rx['bytes']} B\nNOTIFY: {rx['notifyCount']} 次，"
                f"最近一包: {int(rx['lastNotify'])}")
        if "lastWindow" in rx:
            text += f"\n用途={self.window.itemText(rx['lastWindow'])} 偏移={rx['lastOffset']}"
        if rx["error"]:
            text += f"\n错误: {rx['error']}"
        self.rx_status.setText(text)
