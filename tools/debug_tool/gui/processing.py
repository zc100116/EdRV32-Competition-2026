"""processing.py — PIX/GEO parameter editor, Task T-UI1; host Qt thread.

Independent controls commit after 200 ms idle; scale lock starts enabled.
"""
from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QDoubleSpinBox, QFormLayout, QGroupBox, QLabel,
    QSpinBox, QSlider, QHBoxLayout, QVBoxLayout, QWidget,
)


class ProcessingPanel(QWidget):
    def __init__(self, control, run):
        super().__init__()
        self.setStyleSheet("""
QCheckBox { font-size: 12px; spacing: 7px; min-height: 22px; }
QCheckBox::indicator { width: 14px; height: 14px; border: 1px solid #8b98a9;
    border-radius: 4px; background: white; }
QCheckBox::indicator:checked { background: #2f6bff; border: 1px solid #2f6bff; }
QSpinBox, QDoubleSpinBox { min-height: 20px; padding: 2px 6px; font-size: 12px; }
QGroupBox { font-size: 12px; font-weight: 600; padding-top: 14px; margin-top: 8px; }
QGroupBox::title { subcontrol-origin: margin; left: 5px; }
""")
        self.control = control
        self.run = run
        self.inputs = {'pix': {}, 'geo': {}}
        self.timers = {}
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        note = QLabel('参数修改后 200 ms 自动下发。比例 1.000 表示原尺寸；正角度顺时针。')
        note.setWordWrap(True)
        root.addWidget(note)
        for kind in ('pix', 'geo'):
            timer = QTimer(self)
            timer.setSingleShot(True)
            timer.setInterval(200)
            timer.timeout.connect(lambda k=kind: self.run(lambda: self.send(k)))
            self.timers[kind] = timer
        point = self.group(root, '点运算 1')
        self.check(point, 'pix', 'bc', '亮度 / 对比度')
        self.number(point, 'pix', 'contrast', '对比度（Q8，256 = 1 倍）', 0, 511, 256)
        self.number(point, 'pix', 'brightness', '亮度', -256, 255, 0)
        self.check(point, 'pix', 'gamma_en', 'Gamma 校正')
        self.number(point, 'pix', 'gamma', 'Gamma', .001, 2147483.647, 1, 3, 1000)
        stages = self.group(root, '3 × 3 滤波 · 可同时启用两级')
        for key, title in [('stage1', '第一级'), ('stage2', '第二级')]:
            combo = QComboBox()
            combo.addItems(['关闭 / 旁路', '均值', '高斯', '锐化', 'Sobel 边缘', '腐蚀', '膨胀'])
            combo.currentIndexChanged.connect(lambda _, k='pix': self.changed(k))
            stages.addRow(title, combo)
            self.inputs['pix'][key] = combo
        point2 = self.group(root, '点运算 2')
        self.check(point2, 'pix', 'gray', '灰度')
        self.check(point2, 'pix', 'binary', '二值化')
        self.number(point2, 'pix', 'threshold', '二值化阈值', 0, 255, 128)
        self.check(point2, 'pix', 'invert', '反色')
        geometry = self.group(root, '几何变换')
        self.check(geometry, 'geo', 'enabled', '启用几何变换')
        self.number(geometry, 'geo', 'angle', '旋转角度（°）', -214748364.7,
                    214748364.7, 0, 1, 10)
        self.lock_scale = QCheckBox('锁定比例')
        self.lock_scale.setChecked(True)
        self.lock_scale.toggled.connect(self.lock_changed)
        geometry.addRow(self.lock_scale)
        for key, title in [('scale_x', 'X 缩放比例'), ('scale_y', 'Y 缩放比例')]:
            self.number(geometry, 'geo', key, title, .001, 2147483.647, 1, 3, 1000)
        for key, title in [('translate_x', 'X 平移（像素）'), ('translate_y', 'Y 平移（像素）')]:
            self.number(geometry, 'geo', key, title, -2147483647, 2147483647, 0)
        self.check(geometry, 'geo', 'mirror_x', '水平镜像')
        self.check(geometry, 'geo', 'mirror_y', '垂直镜像')
        root.addStretch()

    def group(self, root, title):
        group = QGroupBox(title)
        fields = QFormLayout(group)
        fields.setRowWrapPolicy(QFormLayout.WrapLongRows)
        fields.setFieldGrowthPolicy(QFormLayout.AllNonFixedFieldsGrow)
        root.addWidget(group)
        return fields

    def check(self, form, kind, key, title):
        widget = QCheckBox(title)
        widget.toggled.connect(lambda _: self.changed(kind, key))
        form.addRow(widget)
        self.inputs[kind][key] = widget

    def number(self, form, kind, key, title, low, high, value, decimals=0, factor=1):
        widget = QDoubleSpinBox() if decimals else QSpinBox()
        if decimals:
            widget.setDecimals(decimals)
        widget.lineEdit().setStyleSheet('border:0; padding:0; min-height:0; color:#33404d;')
        widget.setRange(low, high)
        widget.setValue(value)
        widget.setProperty('wireFactor', factor)
        widget.setToolTip(title)
        widget.valueChanged.connect(lambda _: self.changed(kind, key))
        if kind == 'pix' and key in ('contrast', 'brightness', 'threshold'):
            row = QHBoxLayout()
            slider = QSlider(Qt.Horizontal)
            slider.setRange(low, high)
            slider.setValue(value)
            slider.setToolTip(title)
            slider.valueChanged.connect(widget.setValue)
            widget.valueChanged.connect(slider.setValue)
            widget.setMaximumWidth(86)
            row.addWidget(slider, 1)
            row.addWidget(widget)
            form.addRow(title, row)
        else:
            form.addRow(title, widget)
        self.inputs[kind][key] = widget

    def lock_changed(self, locked):
        if locked:
            self.inputs['geo']['scale_y'].setValue(self.inputs['geo']['scale_x'].value())

    def changed(self, kind, key=None):
        if kind == 'geo' and key in ('scale_x', 'scale_y') and self.lock_scale.isChecked():
            other = self.inputs['geo']['scale_y' if key == 'scale_x' else 'scale_x']
            other.blockSignals(True)
            other.setValue(self.inputs['geo'][key].value())
            other.blockSignals(False)
        self.timers[kind].start()

    def send(self, kind):
        values = {}
        for key, widget in self.inputs[kind].items():
            if isinstance(widget, QCheckBox):
                value = int(widget.isChecked())
            elif isinstance(widget, QComboBox):
                value = widget.currentIndex()
            else:
                value = round(widget.value() * widget.property('wireFactor'))
            values[key] = value
        return self.control.send(kind, values)
