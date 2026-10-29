"""video.py — B2 design 3.4a/3.6 live RGB565 preview; host Qt thread.

Paint detections in display coordinates over the corresponding frame_id.
Output controls use the shared configurable UART scene command channel.
"""

from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QColor, QImage, QPainter, QPen
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QFormLayout, QHBoxLayout, QLabel, QPushButton,
    QSpinBox, QVBoxLayout, QWidget,
)
from gui.telemetry import card


class DetectionView(QWidget):
    def __init__(self):
        super().__init__()
        self.image = QImage()
        self.boxes = ()
        self.setMinimumSize(480, 290)

    def set_image(self, image, boxes):
        self.image = image
        self.boxes = boxes
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor('#102237'))
        if self.image.isNull():
            painter.setPen(QColor('#9aafc5'))
            painter.drawText(self.rect(), Qt.AlignCenter, '等待图像与检测结果')
            return
        size = self.image.size().scaled(self.size(), Qt.KeepAspectRatio)
        left = (self.width() - size.width()) / 2
        top = (self.height() - size.height()) / 2
        target = QRectF(left, top, size.width(), size.height())
        painter.drawImage(target, self.image)
        font = painter.font()
        font.setPixelSize(round(14 * 1280 / size.width()))
        painter.setFont(font)
        painter.translate(left, top)
        painter.scale(size.width() / 1280, size.height() / 720)
        pen = QPen(QColor('#45f5b6'), 2)
        pen.setCosmetic(True)
        painter.setPen(pen)
        for x0, y0, x1, y1, class_id, score in self.boxes:
            painter.drawRect(QRectF(x0, y0, x1 - x0, y1 - y0))
            painter.fillRect(QRectF(x0, y0 - 27, 170, 27), QColor('#102e37'))
            painter.drawText(QRectF(x0 + 6, y0 - 27, 165, 27), Qt.AlignVCenter,
                             f'COCO {class_id} · {score / 1000:.3f}')


class VideoPanel(QWidget):
    def __init__(self, engine, toast):
        super().__init__()
        self.engine = engine
        self.toast = toast
        self.last_frame = None
        self.last_boxes = None
        layout = QHBoxLayout(self)
        controls, box = card('视频 · 输出与接收')
        form = QFormLayout()
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        self.port.setValue(6000)
        form.addRow('PC UDP 端口', self.port)
        self.output = QComboBox()
        self.output.addItems(['HDMI', '网口', '同时'])
        form.addRow('输出选择', self.output)
        self.fps = QSpinBox()
        self.fps.setRange(1, 60)
        self.fps.setValue(30)
        form.addRow('网口帧率 fps', self.fps)
        box.addLayout(form)
        apply = QPushButton('下发输出与帧率')
        apply.clicked.connect(self._apply)
        box.addWidget(apply)
        self.listen = QPushButton('开始接收视频')
        self.listen.setObjectName('primary')
        self.listen.clicked.connect(self._listen)
        box.addWidget(self.listen)
        self.overlay = QCheckBox('叠加 WIN 2 检测框')
        self.overlay.setChecked(True)
        box.addWidget(self.overlay)
        self.stats = QLabel('帧率 —\n丢帧 0\n网口跳帧 0')
        self.stats.setWordWrap(True)
        box.addWidget(self.stats)
        note = QLabel('EDVF · RGB565 · WIN 0\nEDDT · 检测结果 · WIN 2\n'
                      '检测框按 frame_id 对应；缺包帧丢弃。\n'
                      '输出命令由 scenes.json 配置。')
        note.setWordWrap(True)
        box.addWidget(note)
        box.addStretch()
        layout.addWidget(controls, 1)
        preview, box = card('视频 · 实时画面')
        self.view = DetectionView()
        box.addWidget(self.view, 1)
        self.caption = QLabel('等待 EDVF 视频帧')
        box.addWidget(self.caption)
        layout.addWidget(preview, 3)

    def _apply(self):
        try:
            self.engine.scenes.send(['output_hdmi', 'output_eth', 'output_both'][
                self.output.currentIndex()])
            self.engine.scenes.send('video_fps', self.fps.value())
        except (ValueError, RuntimeError, OSError) as exc:
            self.toast.show_message(str(exc), error=True)

    def _listen(self):
        try:
            if self.engine.ethernet.status()['rx']['active']:
                self.engine.ethernet.stop_receive()
            else:
                self.engine.ethernet.start_receive(self.port.value(), mode='video')
        except (OSError, RuntimeError) as exc:
            self.toast.show_message(str(exc), error=True)

    def refresh(self):
        state = self.engine.video.snapshot()
        rx = self.engine.ethernet.status()['rx']
        active = rx['active']
        self.listen.setText('停止接收视频' if active else '开始接收视频')
        skipped = self.engine.telemetry.status()['video_skipped']
        self.stats.setText(f"接收帧率  {state['fps']:.1f} fps\n"
                           f"完整帧  {state['received']}\n缺包丢帧  {state['dropped']}\n"
                           f"网口跳帧  {skipped}" +
                           (f"\n错误: {rx['error']}" if rx['error'] else ''))
        frame, detections = state['frame'], state['detections']
        if frame is None:
            return
        boxes = (detections.boxes if self.overlay.isChecked() and detections is not None
                 and detections.frame_id == frame.frame_id else ())
        if frame is not self.last_frame or boxes != self.last_boxes:
            image = QImage(frame.pixels, frame.width, frame.height, frame.stride,
                           QImage.Format_RGB16).copy()
            self.view.set_image(image, boxes)
            self.last_frame, self.last_boxes = frame, boxes
            self.caption.setText(f'FRAME {frame.frame_id} · {frame.width} × {frame.height} · '
                                 f'S{frame.scene} · {len(boxes)} 个检测框')
