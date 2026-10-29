"""yolo.py — B2 design 3.4/3.5a model and image transfers; host Qt thread.

The shared ETH listener saves WIN0/1/2 at exact byte offsets.
Reference inference uses the returned CH2 bytes and compiler model directory.
"""

import json
from pathlib import Path
import threading
import struct

from PySide6.QtCore import Qt
from PySide6.QtGui import QImage
from gui.video import DetectionView

from PySide6.QtWidgets import (
    QComboBox, QFileDialog, QFormLayout, QHBoxLayout, QLabel, QLineEdit,
    QProgressBar, QPushButton, QSpinBox, QWidget,
)
from core.ethernet import DEFAULT_SAVE_DIR
from gui.telemetry import card


class YoloPanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine = engine
        self.toast = toast
        self.generation = -1
        self.comparison = None
        self.comparing = False
        layout = QHBoxLayout(self)
        frame, box = card('YOLO · 数据发送')
        form = QFormLayout()
        self.ip = QLineEdit('192.168.1.10')
        self.board_port = QSpinBox()
        self.board_port.setRange(1, 65535)
        self.board_port.setValue(5000)
        self.local_port = QSpinBox()
        self.local_port.setRange(1, 65535)
        self.local_port.setValue(6000)
        form.addRow('板子 IP', self.ip)
        form.addRow('板子 RX_PORT', self.board_port)
        form.addRow('PC 本地端口', self.local_port)
        box.addLayout(form)
        self.model = QLineEdit()
        self.model.setPlaceholderText('compile_yolo.py 输出目录')
        box.addWidget(self.model)
        choose = QPushButton('选择编译输出目录')
        choose.clicked.connect(self._model_path)
        box.addWidget(choose)
        send = QPushButton('发送描述符与模型 · WIN 2')
        send.setObjectName('primary')
        send.clicked.connect(lambda: self._send(True))
        box.addWidget(send)
        self.image = QLineEdit()
        self.image.setPlaceholderText('测试图片 → 1280 × 720 RGB565')
        box.addWidget(self.image)
        choose = QPushButton('选择测试图片')
        choose.clicked.connect(self._image_path)
        box.addWidget(choose)
        self.window = QComboBox()
        self.window.addItems(['窗口 0', '窗口 1'])
        box.addWidget(self.window)
        send = QPushButton('转换并发送图片')
        send.clicked.connect(lambda: self._send(False))
        box.addWidget(send)
        self.progress = QProgressBar()
        box.addWidget(self.progress)
        self.status = QLabel('尚未发送')
        self.status.setWordWrap(True)
        box.addWidget(self.status)
        self.expected = QLabel('WIN2_BYTES 期望值：—；板端校验结果由串口控制台显示。')
        self.expected.setWordWrap(True)
        box.addWidget(self.expected)
        box.addStretch()
        layout.addWidget(frame, 1)
        frame, box = card('YOLO · 板端数据回传')
        self.directory = QLineEdit(str(DEFAULT_SAVE_DIR))
        box.addWidget(self.directory)
        self.listen = QPushButton('开始接收')
        self.listen.clicked.connect(self._listen)
        box.addWidget(self.listen)
        box.addWidget(QLabel('WIN 0 → CH2 输入 · 983,040 B\n'
                             'WIN 1 → NPU OUTPUT · 725,760 B\n'
                             'WIN 2 → EDDT 检测结果\n'
                             '按 OFFSET 保存为 window0/1/2.bin。'))
        self.received = QLabel('等待板端回传')
        self.received.setWordWrap(True)
        box.addWidget(self.received)
        box.addStretch()
        layout.addWidget(frame, 1)
        frame, box = card('YOLO · 检测与参考比对')
        self.view = DetectionView()
        box.addWidget(self.view, 1)
        self.quant = QLineEdit(str(Path(__file__).resolve().parents[3] /
                                   'build/npu/quantized/quantization.json'))
        self.quant.setPlaceholderText('quantize.py 的 quantization.json')
        box.addWidget(self.quant)
        choose = QPushButton('选择后处理量化 JSON')
        choose.clicked.connect(self._quant_path)
        box.addWidget(choose)
        self.compare_button = QPushButton('运行参考模型并比对')
        self.compare_button.setObjectName('primary')
        self.compare_button.clicked.connect(self._compare)
        box.addWidget(self.compare_button)
        self.result = QLabel('等待完整回传；参考模型在后台执行。')
        self.result.setWordWrap(True)
        box.addWidget(self.result)
        layout.addWidget(frame, 3)

    def _quant_path(self):
        path, _ = QFileDialog.getOpenFileName(self, '后处理量化参数', filter='JSON (*.json)')
        if path:
            self.quant.setText(path)

    def _compare(self):
        if self.comparing:
            return
        image, directory, quant = self.image.text(), self.model.text(), self.quant.text()
        self.comparing = True
        self.comparison = None
        self.result.setText('参考模型运行中…')

        def run():
            try:
                parameters = json.loads(Path(quant).read_text(encoding='utf-8'))
                self.comparison = self.engine.yolo.compare(image, directory, parameters)
            except (OSError, ValueError, RuntimeError, ImportError, KeyError, struct.error) as exc:
                self.comparison = str(exc)
            finally:
                self.comparing = False
        threading.Thread(target=run, name='yolo-reference', daemon=True).start()

    def _model_path(self):
        path = QFileDialog.getExistingDirectory(self, '选择 compile_yolo 输出目录')
        if path:
            self.model.setText(path)

    def _image_path(self):
        path, _ = QFileDialog.getOpenFileName(self, '选择测试图片')
        if path:
            self.image.setText(path)
            image = QImage(path).scaled(1280, 720, Qt.IgnoreAspectRatio,
                                        Qt.SmoothTransformation)
            self.view.set_image(image, ())

    def _send(self, model):
        try:
            send = self.engine.yolo.send_model if model else self.engine.yolo.send_image
            options = {} if model else {'window': self.window.currentIndex()}
            send(self.model.text() if model else self.image.text(), self.ip.text(),
                 self.board_port.value(), self.local_port.value(), **options)
            if model:
                self.expected.setText(f'WIN2_BYTES 期望 {self.engine.yolo.image_bytes:,} B；'
                                      '板端校验结果由串口控制台显示。')
        except (OSError, ValueError, RuntimeError, KeyError) as exc:
            self.toast.show_message(str(exc), error=True)

    def _listen(self):
        try:
            if self.engine.ethernet.status()['rx']['active']:
                self.engine.ethernet.stop_receive()
            else:
                self.engine.ethernet.start_receive(
                    self.local_port.value(), self.directory.text(), mode='yolo')
        except (OSError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)

    def refresh(self):
        state = self.engine.ethernet.status()
        tx, rx = state['tx'], state['rx']
        self.progress.setValue(int(tx['sent'] / tx['total'] * 100) if tx['total'] else 0)
        self.status.setText(f"{tx['sent']:,} / {tx['total']:,} B · "
                            f"{tx['error'] or ('发送中' if tx['active'] else '就绪')}")
        self.listen.setText('停止接收' if rx['active'] else '开始接收')
        complete = rx.get('lastWindow') == 2 and rx['lastNotify']
        self.received.setText(f"{'三块回传完毕' if complete else '接收数据'} · "
                              f"{rx['bytes']:,} B\n" +
                              '\n'.join(f'WIN {key}: {path}' for key, path in rx['files'].items()) +
                              (f"\n错误: {rx['error']}" if rx['error'] else ''))

        generation, capture = self.engine.yolo.snapshot()
        if capture is not None and generation != self.generation:
            self.generation = generation
            self.result.setText('完整回传已收到；选择模型和量化参数后运行参考比对。')
            detections = capture[2]
            image = QImage(self.image.text()).scaled(1280, 720, Qt.IgnoreAspectRatio,
                                                     Qt.SmoothTransformation)
            self.view.set_image(image, detections.boxes)
        if capture is not None:
            detections = capture[2]
            self.received.setText(f'三块回传完毕 · FRAME {detections.frame_id} · '
                                  f'{len(detections.boxes)} 个检测框')
        self.compare_button.setEnabled(not self.comparing)
        if self.comparison is not None:
            if isinstance(self.comparison, str):
                self.result.setText('参考比对失败: ' + self.comparison)
            else:
                result = self.comparison
                first = result['output']['first']
                first_text = '无' if first is None else f'{first} / 0x{first:x}'
                self.result.setText(
                    f"CH2 输入差异: {result['input']['count']:,} 字节\n"
                    f"NPU OUTPUT 差异: {result['output']['count']:,} 字节\n"
                    f"首个 OUTPUT 差异位置: {first_text}\n"
                    f"后处理检测差异: {result['detections']['count']} 个框 "
                    f"(参考 {result['detections']['expected']} / "
                    f"板端 {result['detections']['actual']})")
