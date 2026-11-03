"""video.py — B2 design 3.4a/3.6 live RGB565 preview; host Qt thread.

Paint detections in display coordinates over the corresponding frame_id.
Detection annotations retain readable text as the shared canvas scales.
"""

from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QColor, QImage, QPainter, QPen
from PySide6.QtWidgets import QWidget

from core.labels import COCO_NAMES


def detection_label(class_id, score):
    return f'{COCO_NAMES[class_id]} · {score / 1000:.3f}'


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
        font.setPixelSize(11)
        painter.setFont(font)
        painter.setPen(QPen(QColor('#45f5b6'), 2))
        labels = []
        for x0, y0, x1, y1, class_id, score in self.boxes:
            x = left + x0 * size.width() / self.image.width()
            y = top + y0 * size.height() / self.image.height()
            painter.drawRect(QRectF(x, y, (x1 - x0) * size.width() / self.image.width(),
                                   (y1 - y0) * size.height() / self.image.height()))
            text = detection_label(class_id, score)
            width = painter.fontMetrics().horizontalAdvance(text) + 10
            height = painter.fontMetrics().height() + 6
            bounds = QRectF(min(x, self.width() - width), max(0, y - height), width, height)
            # Pack annotations above one another when a small canvas brings boxes close.
            while any(bounds.intersects(previous) for previous in labels):
                bounds.moveTop(bounds.top() - height - 2)
            labels.append(bounds)
            painter.fillRect(bounds, QColor('#102e37'))
            painter.drawText(bounds.adjusted(5, 0, -5, 0), Qt.AlignVCenter, text)
