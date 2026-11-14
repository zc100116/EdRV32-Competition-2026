"""pipeline.py — vision pipeline design 4 / 7, host Qt thread.
Drag blocks from the library or reorder the chain; board state owns acceptance.
"""
import copy
import json

from PySide6.QtCore import QMimeData, Qt, Signal, QSize
from PySide6.QtGui import QDrag
from PySide6.QtWidgets import (
    QAbstractItemView, QCheckBox, QComboBox, QFormLayout,
    QHBoxLayout, QLabel, QListWidget, QListWidgetItem, QProgressBar, QPushButton,
    QSpinBox, QVBoxLayout, QWidget,
)
from core.pipeline import NAMES, FILTERS, PRESETS, ENGINES, PARAMS, block

MIME = 'application/x-vision-block'


def text(value):
    label = QLabel(value)
    label.setWordWrap(True)
    return label


class BlockList(QListWidget):
    edited = Signal()

    def __init__(self, library=False):
        super().__init__()
        self.library = library
        self.setDragEnabled(True)
        self.setAcceptDrops(not library)
        self.setDropIndicatorShown(True)
        self.setDefaultDropAction(Qt.MoveAction)
        self.setSelectionMode(QAbstractItemView.SingleSelection)
        self.setSpacing(5)
        self.setTextElideMode(Qt.ElideNone)
        if not library:
            self.setFlow(QListWidget.LeftToRight)
            self.setWrapping(False)
            self.setFixedHeight(70)
        self.setStyleSheet('QListWidget {background:#edf2f8;border:0;border-radius:8px;}'
                           'QListWidget::item {background:white;border:1px solid #c9d8eb;'
                           'border-radius:7px;padding:8px;color:#33445b;}'
                           'QListWidget::item:selected {background:#e3edff;'
                           'border:1px solid #2f6bff;}')

    def startDrag(self, actions):
        item = self.currentItem()
        if item is None:
            return
        mime = QMimeData()
        mime.setData(MIME, json.dumps(dict(index=-1 if self.library else self.currentRow(),
                                         block=item.data(Qt.UserRole))).encode())
        drag = QDrag(self)
        drag.setMimeData(mime)
        drag.exec(Qt.CopyAction if self.library else Qt.MoveAction)

    def dragEnterEvent(self, event):
        if event.mimeData().hasFormat(MIME) and not self.library:
            event.acceptProposedAction()

    def dragMoveEvent(self, event):
        self.dragEnterEvent(event)

    def dropEvent(self, event):
        data = json.loads(bytes(event.mimeData().data(MIME)))
        target = self.indexAt(event.position().toPoint()).row()
        self.move_block(data['index'], self.count() if target < 0 else target, data['block'])
        event.acceptProposedAction()

    def move_block(self, origin, target, value):
        if origin >= 0:
            self.takeItem(origin)
            if target > origin:
                target -= 1
        self.insertItem(target, self.make_item(value))
        self.setCurrentRow(target)
        self.edited.emit()

    @staticmethod
    def make_item(value):
        kind = value['type']
        detail = FILTERS[value['p'][0] - 1] if kind == 3 else (
            f"{value['p'][0]}° · {value['p'][1]}%" if kind == 7 else
            ' + '.join(name for bit, name in ((1, '检测框'), (2, '界面'))
                       if value['flags'] & bit) if kind == 9 else '取样点' if kind == 8 else '')
        item = QListWidgetItem(NAMES[kind] + ('\n' + detail if detail else ''))
        item.setData(Qt.UserRole, copy.deepcopy(value))
        item.setSizeHint(QSize(max(100, len(NAMES[kind]) * 15 + 20), 51))
        return item


class PipelinePanel(QWidget):
    def __init__(self, engine, run):
        super().__init__()
        self.engine, self.run = engine, run
        self.revision = -1
        self.last_stats = None
        self.draft = engine.pipeline.status()
        self.setFixedHeight(270)
        root = QVBoxLayout(self)
        root.setContentsMargins(8, 6, 8, 6)
        root.setSpacing(4)
        header = QHBoxLayout()
        title = text('视觉流水线')
        title.setStyleSheet('font-size:17px;font-weight:700;color:#2157bc;')
        header.addWidget(title)
        self.source = QComboBox()
        self.source.addItems(['摄像头', 'PC 图片', '测试图'])
        header.addWidget(self.source)
        header.addStretch()
        header.addWidget(text('拖入积木 · 拖动排序 · 选中编辑'))
        root.addLayout(header)
        presets = QHBoxLayout()
        self.presets = []
        for number, name in enumerate(PRESETS, 1):
            button = QPushButton(name)
            button.clicked.connect(lambda checked=False, n=number: self.run(
                lambda: engine.pipeline.preset(n)))
            presets.addWidget(button)
            self.presets.append(button)
        root.addLayout(presets)
        row = QHBoxLayout()
        self.source_view = QPushButton('来源\n看此级 →')
        self.source_view.setToolTip('看此级：显示来源原图')
        self.source_view.clicked.connect(lambda: self.change_view(254))
        row.addWidget(self.source_view)
        self.chain = BlockList()
        row.addWidget(self.chain, 1)
        row.addWidget(text('→ HDMI'))
        root.addLayout(row)
        self.metrics = text('硬件路径 · 等待板端统计')
        self.metrics.setStyleSheet('font-weight:600;color:#2157bc;')
        self.metrics.setWordWrap(False)
        root.addWidget(self.metrics)
        self.hops = QHBoxLayout()
        root.addLayout(self.hops)
        bandwidth = QHBoxLayout()
        self.ddr = QProgressBar()
        self.ddr.setRange(0, 1950)
        self.ddr.setTextVisible(False)
        self.ddr.setMaximumHeight(9)
        self.ddr_text = text('DDR — / 1.95 GB/s')
        self.ddr_text.setWordWrap(False)
        bandwidth.addWidget(self.ddr, 1)
        bandwidth.addWidget(self.ddr_text)
        root.addLayout(bandwidth)
        self.notice = text('最多 8 块积木 · 检测最多 1 块 · 超出预算时帧率下降')
        root.addWidget(self.notice)
        self.details = QWidget()
        detail = QVBoxLayout(self.details)
        detail.setContentsMargins(0, 0, 0, 0)
        detail.addWidget(text('积木库 · 拖入链中，也可双击添加'))
        self.library = BlockList(True)
        self.library.setFixedHeight(160)
        self.library.setViewMode(QListWidget.IconMode)
        self.library.setResizeMode(QListWidget.Adjust)
        self.library.setWrapping(True)
        for kind in range(1, 10):
            item = BlockList.make_item(block(kind, 1 if kind == 9 else 0))
            item.setText(NAMES[kind])
            self.library.addItem(item)
        detail.addWidget(self.library)
        self.library.itemDoubleClicked.connect(lambda item: self.chain.move_block(
            -1, self.chain.count(), item.data(Qt.UserRole)))
        actions = QHBoxLayout()
        for title, callback in (('删除选中', self.delete), ('看此级', self.view_selected),
                                ('看原图', lambda: self.change_view(254)),
                                ('最终输出', lambda: self.change_view(255))):
            button = QPushButton(title)
            button.clicked.connect(callback)
            actions.addWidget(button)
        detail.addLayout(actions)
        self.editor_title = text('选中积木后编辑参数')
        detail.addWidget(self.editor_title)
        self.editor = QFormLayout()
        detail.addLayout(self.editor)
        self.chain.edited.connect(self.submit)
        self.chain.currentRowChanged.connect(self.edit)
        self.source.currentIndexChanged.connect(self.submit)
        self.refresh()

    def refresh(self):
        board = self.engine.board
        if self.revision != board.chain_rev:
            self.revision = board.chain_rev
            self.draft = self.engine.pipeline.status()
            self.source.blockSignals(True)
            self.source.setCurrentIndex(self.draft['source'])
            self.source.blockSignals(False)
            selected = self.chain.currentRow()
            self.chain.clear()
            for value in self.draft['blocks']:
                self.chain.addItem(BlockList.make_item(value))
            self.chain.setCurrentRow(min(max(selected, 0), self.chain.count() - 1))
        self.notice.setText(board.error or
            '最多 8 块积木 · 检测最多 1 块 · 超出预算时帧率下降')
        self.notice.setStyleSheet('color:#c03950;' if board.error else 'color:#708096;')
        stats = board.pipe_stats
        if stats is None or stats == self.last_stats:
            return
        self.last_stats = copy.deepcopy(stats)
        self.metrics.setText(f"硬件路径 · {stats['fps']} fps · 端到端 "
                             f"{stats['e2e_us'] / 1000:.1f} ms · 框滞后 "
                             f"{stats['box_lag_us'] / 1000:.1f} ms · "
                             f"NPU {stats['npu_us'] / 1000:.1f} ms")
        while self.hops.count():
            old = self.hops.takeAt(0).widget()
            old.hide()
            old.deleteLater()
        for index, hop in enumerate(stats['hops']):
            span = ('来源' if hop['first'] == 255 else
                    f"积木 {hop['first'] + 1}–{hop['last'] + 1}")
            value = text(f"{index + 1:02}  {ENGINES[hop['engine']]}\n"
                         f"{span} · {hop['us'] / 1000:.1f} ms")
            value.setStyleSheet('background:#e8eff9;border-radius:5px;padding:5px;')
            self.hops.addWidget(value, 1)
        self.ddr.setValue(stats['ddr_mbps'])
        self.ddr_text.setText(f"DDR {stats['ddr_mbps'] / 1000:.2f} / 1.95 GB/s")

    def submit(self, *_):
        self.draft.update(source=self.source.currentIndex(), preset=0,
                          blocks=[self.chain.item(i).data(Qt.UserRole)
                                  for i in range(self.chain.count())])
        self.run(lambda: self.engine.pipeline.send(copy.deepcopy(self.draft)))

    def delete(self):
        if self.chain.currentRow() >= 0:
            self.chain.takeItem(self.chain.currentRow())
            self.draft['view'] = 255
            self.submit()

    def view_selected(self):
        if self.chain.currentRow() >= 0:
            self.change_view(self.chain.currentRow())

    def change_view(self, value):
        self.draft['view'] = value
        self.submit()

    def edit(self, row):
        while self.editor.rowCount():
            self.editor.removeRow(0)
        if row < 0:
            return
        value = self.chain.item(row).data(Qt.UserRole)
        kind = value['type']
        self.editor_title.setText(f'{row + 1} · {NAMES[kind]}')
        for index, (name, low, high) in enumerate(PARAMS.get(kind, ())):
            if kind == 3:
                field = QComboBox()
                field.addItems(FILTERS)
                field.setCurrentIndex(value['p'][index] - 1)
                field.currentIndexChanged.connect(
                    lambda v, i=index: self.parameter(i, v + 1))
            else:
                field = QSpinBox()
                field.setRange(low, high)
                field.setValue(value['p'][index])
                field.setMinimumWidth(120)
                field.setKeyboardTracking(False)
                field.valueChanged.connect(lambda v, i=index: self.parameter(i, v))
            self.editor.addRow(name, field)
        flags = ('水平镜像', '垂直镜像') if kind == 7 else (
            ('检测框', '界面') if kind == 9 else ())
        for index, name in enumerate(flags):
            field = QCheckBox(name)
            field.setChecked(bool(value['flags'] & (1 << index)))
            field.toggled.connect(lambda v, i=index: self.flag(i, v))
            self.editor.addRow(field)
        if kind == 8:
            self.editor.addRow(text('置信度门槛和类别在下方「检测设置」中编辑'))
        elif kind in (4, 6):
            self.editor.addRow(text('此积木没有参数'))

    def parameter(self, index, value):
        item = self.chain.currentItem()
        data = item.data(Qt.UserRole)
        data['p'][index] = value
        item.setData(Qt.UserRole, data)
        item.setText(BlockList.make_item(data).text())
        self.submit()

    def flag(self, index, value):
        item = self.chain.currentItem()
        data = item.data(Qt.UserRole)
        data['flags'] = ((data['flags'] & ~(1 << index)) | (int(value) << index))
        item.setData(Qt.UserRole, data)
        item.setText(BlockList.make_item(data).text())
        self.submit()
