"""Live-demo L3: real UDP fake board, localhost phone and DEMO ACK ownership."""
import json
import socket
import struct
import unittest
from unittest.mock import patch

from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.demo import read_demo
from tools.debug_tool.core.showcase import ACK, DEMO, HELLO, STATE
from tools.debug_tool.core.virtual_input import FRAME
import test_p5_protocol as p5
from test_p5_protocol import state_payload
from test_program import wait_for


class LiveDemoTest(unittest.TestCase):
    setUp = p5.ProtocolTest.setUp
    reply = p5.ProtocolTest.reply
    request = p5.ProtocolTest.request

    def test_demo_ack_serialization_and_error(self):
        tool = self.eth.showcase
        for action, arg in ((0, 10), (1, 0), (2, 0), (3, 3), (4, 0)):
            command = tool.demo(action, arg)
            kind, seq, payload = self.request()
            self.assertEqual((kind, payload), (DEMO, struct.pack('<BB2x', action, arg)))
            self.assertEqual(command['seq'], seq)
            self.reply(ACK, seq, struct.pack('<HBB', DEMO, 1, 0))
            wait_for(self, lambda: tool.pending[DEMO]['phase'] == 1)
            with self.assertRaisesRegex(RuntimeError, '同类命令'):
                tool.demo(1, 0)
            self.reply(ACK, seq, struct.pack('<HBB', DEMO, 2, 0))
            wait_for(self, lambda: DEMO not in tool.pending)
        tool.demo(0, 11)
        _, seq, _ = self.request()
        self.reply(ACK, seq, struct.pack('<HBB', DEMO, 3, 2))
        wait_for(self, lambda: DEMO not in tool.pending)
        self.assertIn('格式错误', self.engine.board.error)
        tool.demo(0, 1)
        self.assertEqual(self.request()[0], DEMO)

    def test_proto_and_state_and_rest(self):
        payload = bytearray(state_payload())
        payload[5:8] = bytes((255, 3, 123))
        with self.assertRaisesRegex(ValueError, 'expected 4'):
            self.engine.board.receive_state(HELLO, struct.pack('<H2x16s', 3, b'old') + payload)
        with patch.object(self.engine.virtual_input, 'start'):
            self.engine.board.receive_state(HELLO, struct.pack('<H2x16s', 4, b'new') + payload)
        server = ApiServer(self.engine, port=0)
        server.start()
        self.addCleanup(server.stop)
        import urllib.request
        url = f'http://127.0.0.1:{server._httpd.server_port}'
        with urllib.request.urlopen(url + '/api/board') as response:
            state = json.load(response)['state']
        self.assertEqual([state[k] for k in ('demo_scene', 'preset', 'luma')], [255, 3, 123])
        request = urllib.request.Request(url + '/api/demo', b'{"action":0,"arg":10}',
                                         {'Content-Type': 'application/json'})
        with urllib.request.urlopen(request) as response:
            self.assertIn('seq', json.load(response))
        self.assertEqual(self.request()[2], bytes((0, 10, 0, 0)))

    def test_phone_lines_state_periodic_pad_disconnect_reconnect(self):
        listener = socket.socket()
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', 47633))
        listener.listen()
        listener.settimeout(3)
        self.addCleanup(listener.close)
        relay = self.engine.phone_relay
        self.addCleanup(relay.close)
        relay.connect('127.0.0.1')
        phone, _ = listener.accept()
        phone.settimeout(3)
        with phone, phone.makefile('rb') as reader:
            snapshot = json.loads(reader.readline())
            self.assertEqual(snapshot, dict(board=dict(
                connected=False, scene=0, preset=0, luma=0, busy=False)))
            self.assertEqual(json.loads(reader.readline()), snapshot)
            payload = bytearray(state_payload())
            payload[5:8] = bytes((10, 2, 99))
            with patch.object(self.engine.virtual_input, 'start'):
                self.engine.board.receive_state(HELLO, struct.pack('<H2x16s', 4, b'new') + payload)
            snapshot = json.loads(reader.readline())
            self.assertEqual(snapshot['board'], dict(
                connected=True, scene=10, preset=2, luma=99, busy=False))
            # Fragmented JSON and multiple lines use exactly the same framing.
            phone.sendall(b'{"demo":{"action":0,')
            phone.sendall(b'"arg":10}}\n')
            kind, seq, payload = self.request()
            self.assertEqual((kind, payload), (DEMO, bytes((0, 10, 0, 0))))
            self.assertTrue(json.loads(reader.readline())['board']['busy'])
            phone.sendall(b'{"demo":{"action":1,"arg":0}}\n')
            wait_for(self, lambda: '同类命令' in relay.error)
            self.assertTrue(relay.connected)
            self.reply(ACK, seq, struct.pack('<HBB', DEMO, 2, 0))
            wait_for(self, lambda: DEMO not in self.eth.showcase.pending)
            self.assertFalse(json.loads(reader.readline())['board']['busy'])
            phone.sendall(b'{"pad":{"keys":17}}\n')
            def pad_frame():
                from tools.debug_tool.core.ethernet import unpack
                window, _, _, data = unpack(self.board.recv(65535))
                self.assertEqual(window, 2)
                return FRAME.unpack(data)
            self.assertEqual(pad_frame(), (17, 0, 0, 0, 0))
            self.assertEqual(pad_frame(), (17, 0, 0, 0, 0))
            phone.sendall(b'{bad}\n')
            wait_for(self, lambda: '手机中继错误' in relay.error)
            self.assertIn('手机中继错误', relay.error)
            wait_for(self, lambda: self.engine.virtual_input.relay_keys == 0)
            self.assertEqual(pad_frame(), (0, 0, 0, 0, 0))
            self.assertEqual(reader.readline(), b'')
        reconnected, _ = listener.accept()
        with reconnected, reconnected.makefile('rb') as reader:
            self.assertTrue(json.loads(reader.readline())['board']['connected'])

    def test_malformed_relay_json(self):
        for line in ('[]', '{}', '{"demo":{}}', '{"demo":{"action":true,"arg":0}}',
                     '{"pad":{"keys":"16"}}'):
            with self.assertRaises(ValueError):
                read_demo(line)

    def test_relay_release_preserves_pc_keys(self):
        self.engine.board.steps['peer']['done'] = True
        virtual = self.engine.virtual_input
        with patch.object(virtual, 'send') as send:
            virtual.update(2, 100, 200, 1)
            virtual.update_relay(16)
            self.assertEqual(FRAME.unpack(send.call_args.args[0]), (18, 0, 0, 0, 0))
            virtual.clear_relay()
            self.assertEqual(FRAME.unpack(send.call_args.args[0]), (2, 100, 200, 1, 0))

    def test_minimized_window_keeps_relay_running(self):
        from PySide6.QtWidgets import QApplication
        from gui.app import MainWindow
        app = QApplication.instance() or QApplication([])
        window = MainWindow(self.engine)
        self.addCleanup(window.close)
        listener = socket.socket()
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', 47633))
        listener.listen()
        listener.settimeout(3)
        self.addCleanup(listener.close)
        window.show()
        window._select_page(7)
        window.showMinimized()
        app.processEvents()
        self.assertTrue(window.isMinimized())
        self.engine.phone_relay.connect('127.0.0.1')
        phone, _ = listener.accept()
        with phone:
            phone.sendall(b'{"demo":{"action":0,"arg":10}}\n')
            self.assertEqual(self.request()[2], bytes((0, 10, 0, 0)))
