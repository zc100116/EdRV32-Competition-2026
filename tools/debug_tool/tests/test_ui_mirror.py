"""L7: frozen UI fragments, REST and real fake-board/localhost phone routing."""
import json
import socket
import struct
import unittest
import urllib.request

from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.demo import read_demo
from tools.debug_tool.core.showcase import ACK, UI_ACT, UI_ITEMS, MESSAGE, decode
from tools.debug_tool.core.ethernet import packets
import test_p5_protocol as p5
from test_program import wait_for


def ui_item(ident, kind, value, minimum, maximum, area, label, options=''):
    label, options = label.encode(), options.encode()
    return (struct.pack('<BBhhhBB', ident, kind, value, minimum, maximum, area, len(label))
            + label + bytes((len(options),)) + options)


def ui_part(part, parts, *items, revision=42, page=4, title='图形引擎'):
    title = title.encode()
    return struct.pack('<IBBBBB', revision, part, parts, page, 0, len(title)) + title + b''.join(items)


class UiMirrorTest(unittest.TestCase):
    setUp = p5.ProtocolTest.setUp
    reply = p5.ProtocolTest.reply
    request = p5.ProtocolTest.request

    def send_ui(self, payload):
        data = MESSAGE.pack(b'EDSC', UI_ITEMS, len(payload), 0) + payload
        self.board.sendto(next(packets(data, 3, 0)), self.destination)

    def test_fragments_signed_values_and_same_revision_updates(self):
        first = ui_part(0, 2, ui_item(0, 0, 0, 0, 0, 0, '开始'),
                        ui_item(1, 1, 1, 0, 0, 0, '统计'))
        second = ui_part(1, 2, ui_item(2, 2, -100, -256, 255, 1, '亮度'),
                         ui_item(3, 3, 1, 0, 0, 1, '模式', '线框\n实体'))
        self.send_ui(second)
        wait_for(self, lambda: 1 in self.eth.showcase.ui.fragments)
        self.assertEqual(self.eth.showcase.ui.snapshot['items'], [])
        self.send_ui(first)
        wait_for(self, lambda: len(self.eth.showcase.ui.snapshot['items']) == 4)
        ui = self.eth.showcase.ui.snapshot
        self.assertEqual((ui['revision'], ui['page'], ui['title']), (42, 4, '图形引擎'))
        self.assertEqual([i['id'] for i in ui['items']], [0, 1, 2, 3])
        self.assertEqual(ui['items'][2], dict(id=2, kind=2, value=-100, min=-256,
                                             max=255, area=1, label='亮度', options=[]))
        self.assertEqual(ui['items'][3]['options'], ['线框', '实体'])
        self.send_ui(ui_part(0, 1, ui_item(2, 2, 25, -256, 255, 1, '亮度')))
        wait_for(self, lambda: self.eth.showcase.ui.snapshot['items'][0]['value'] == 25)
        # UI_ITEMS shares the frozen 1000-byte EDSC payload limit.
        item = ui_item(0, 0, 0, 0, 0, 0, 'x' * 36)
        full = ui_part(0, 1, *([item] * 19),
                       ui_item(0, 0, 0, 0, 0, 0, 'x' * 39), title='x' * 48)
        self.assertEqual(len(full), 1000)
        self.assertEqual(decode(MESSAGE.pack(b'EDSC', UI_ITEMS, 1000, 0) + full)[0], UI_ITEMS)

    def test_rest_and_act_encoding(self):
        self.send_ui(ui_part(0, 1, ui_item(8, 2, -1, -256, 255, 1, '亮度')))
        wait_for(self, lambda: self.eth.showcase.ui.snapshot['revision'] == 42)
        server = ApiServer(self.engine, port=0)
        server.start()
        self.addCleanup(server.stop)
        url = f'http://127.0.0.1:{server._httpd.server_port}'
        with urllib.request.urlopen(url + '/api/ui') as response:
            self.assertEqual(json.load(response), self.eth.showcase.ui.snapshot)
        body = dict(revision=42, id=8, action=1, value=-256)
        request = urllib.request.Request(url + '/api/ui/act', json.dumps(body).encode(),
                                         {'Content-Type': 'application/json'})
        with urllib.request.urlopen(request) as response:
            seq = json.load(response)['seq']
        self.assertEqual(self.request(), (UI_ACT, seq, struct.pack('<IBBh', 42, 8, 1, -256)))
        self.reply(ACK, seq, struct.pack('<HBB', UI_ACT, 2, 0))
        wait_for(self, lambda: UI_ACT not in self.eth.showcase.pending)

    def test_panel_controls_and_custom_preset(self):
        from unittest.mock import patch
        from PySide6.QtWidgets import QApplication, QPushButton, QCheckBox, QSlider, QComboBox
        from gui.demo import DemoPanel
        app = QApplication.instance() or QApplication([])
        self.eth.showcase.ui.receive(ui_part(0, 1,
            ui_item(0, 0, 0, 0, 0, 0, '开始'), ui_item(1, 1, 1, 0, 0, 0, '统计'),
            ui_item(2, 2, -10, -256, 255, 1, '亮度'),
            ui_item(3, 3, 1, 0, 0, 1, '模式', '线框\n实体')))
        self.engine.board.board_state.update(demo_scene=11, preset=255)
        panel = DemoPanel(self.engine)
        self.addCleanup(panel.close)
        self.assertIn('自定义', panel.status.text())
        self.assertIn('11/11', panel.status.text())
        with patch.object(self.eth.showcase, 'ui_act') as act:
            panel.mirror.findChild(QPushButton).click()
            act.assert_called_with(42, 0, 0, 0)
            panel.mirror.findChild(QCheckBox).click()
            act.assert_called_with(42, 1, 0, 0)
            slider = panel.mirror.findChild(QSlider)
            slider.setValue(20)
            act.assert_called_with(42, 1, 0, 0)
            slider.sliderReleased.emit()
            act.assert_called_with(42, 2, 1, 20)
            panel.mirror.findChild(QComboBox).activated.emit(0)
            act.assert_called_with(42, 3, 1, 0)
        app.processEvents()

    def test_unselected_choices_and_read_only_ranges(self):
        from PySide6.QtWidgets import QApplication, QComboBox, QSlider, QLabel
        from gui.demo import DemoPanel
        app = QApplication.instance() or QApplication([])
        self.eth.showcase.ui.receive(ui_part(0, 1,
            ui_item(0, 3, -1, 0, 0, 0, '快捷档', '原始\n降噪'),
            ui_item(1, 3, 9, 0, 0, 0, '模式', '线框\n实体'),
            ui_item(2, 2, 8, 0, 0, 1, '只读值'),
            ui_item(3, 2, -1, 5, -5, 1, '反向范围')))
        panel = DemoPanel(self.engine)
        self.addCleanup(panel.close)
        choices = panel.mirror.findChildren(QComboBox)
        self.assertEqual([control.currentIndex() for control in choices], [-1, -1])
        self.assertEqual([control.placeholderText() for control in choices], ['未选', '未选'])
        self.assertEqual(panel.mirror.findChildren(QSlider), [])
        labels = [label.text() for label in panel.mirror.findChildren(QLabel)]
        self.assertIn('只读值：8', labels)
        self.assertIn('反向范围：-1', labels)
        app.processEvents()

    def test_phone_ui_changes_periodic_and_act(self):
        listener = socket.socket()
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', 47633))
        listener.listen()
        listener.settimeout(3)
        self.addCleanup(listener.close)
        self.addCleanup(self.engine.phone_relay.close)
        self.engine.phone_relay.connect('127.0.0.1')
        phone, _ = listener.accept()
        phone.settimeout(3)
        def read_ui(reader):
            while True:
                message = json.loads(reader.readline())
                if 'ui' in message:
                    return message['ui']
        with phone, phone.makefile('rb') as reader:
            self.assertEqual(read_ui(reader), self.eth.showcase.ui.snapshot)
            self.send_ui(ui_part(0, 1, ui_item(0, 0, 0, 0, 0, 0, '开始')))
            ui = read_ui(reader)
            self.assertEqual(ui['revision'], 42)
            self.assertEqual(read_ui(reader), ui)
            message = dict(ui_act=dict(revision=42, id=0, action=0, value=0))
            wire = json.dumps(message).encode() + b'\n'
            phone.sendall(wire[:15])
            phone.sendall(wire[15:])
            kind, seq, payload = self.request()
            self.assertEqual((kind, payload), (UI_ACT, struct.pack('<IBBh', 42, 0, 0, 0)))
            self.reply(ACK, seq, struct.pack('<HBB', UI_ACT, 3, 5))
            wait_for(self, lambda: UI_ACT not in self.eth.showcase.pending)
            self.assertIn('状态不符', self.engine.board.error)
            message = json.loads(reader.readline())
            while 'ui_error' not in message:
                message = json.loads(reader.readline())
            self.assertEqual(message, dict(ui_error=dict(message='命令失败：状态不符')))
        for value in ('{"ui_act":{}}', '{"ui_act":{"revision":true,"id":0,"action":0,"value":0}}'):
            with self.assertRaises(ValueError):
                read_demo(value)
