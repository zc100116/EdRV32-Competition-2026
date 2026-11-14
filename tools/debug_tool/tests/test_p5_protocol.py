"""P5 8.2–8.5 fake-board tests: connection, ACK serialization and STATE ownership."""
import os
from pathlib import Path
import socket
import struct
import sys
import time
import unittest
from unittest.mock import Mock, patch

from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.ethernet import packets, unpack
from tools.debug_tool.core.pipeline import preset, pack_chain, unpack_chain
from tools.debug_tool.core.showcase import (
    APP, IMAGE_INFO, CHAIN, PRESET, CHAIN_STATE, DETECT, CANCEL, HELLO, STATE, ACK, IMAGE_STEP, encode, decode,
)
from test_program import wait_for

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def state_payload(app=1, state=2, chain_rev=0, threshold=50, classes=(1, 2, 4), request=0):
    return (struct.pack('<5B3x3I', app, state, 0, 1, threshold, *classes) +
            struct.pack('<I20x', chain_rev) +
            struct.pack('<IIB3x', request, 7, 0))


def hello():
    return encode(HELLO, 0, struct.pack('<H2x16s', 3, b'a30c3ee3') + state_payload())


class ProtocolTest(unittest.TestCase):
    def setUp(self):
        self.engine = SerialEngine()
        self.eth = self.engine.ethernet
        self.eth.local_ip = '127.0.0.1'
        self.eth.start_receive(0, mode='files')
        self.addCleanup(self.eth.stop_receive)
        self.addCleanup(self.engine.virtual_input.close)
        self.board = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.board.bind(('127.0.0.1', 0))
        self.board.settimeout(2)
        self.addCleanup(self.board.close)
        self.engine.board.network_endpoint = self.board.getsockname()
        self.destination = self.eth.rx_socket.getsockname()
        self.ready = patch.object(self.eth, 'wait_for_link')
        self.ready.start()
        self.addCleanup(self.ready.stop)

    def reply(self, kind, seq, payload):
        self.board.sendto(next(packets(encode(kind, seq, payload), 3, 0)), self.destination)

    def request(self):
        packet = self.board.recv(65535)
        return decode(unpack(packet)[3])

    def test_hello_only_peer_and_three_seconds_without_state_reconnect(self):
        session = self.engine.board
        with patch.object(self.engine, 'send') as serial:
            session.feed_line('ETH peer IP: 0x7f000001')
            session.feed_line('ETH peer port: 6000')
            self.assertFalse(session.steps['peer']['done'])
            with self.assertRaisesRegex(RuntimeError, '网口未连接'):
                self.engine.virtual_input.update(1, 0, 0, 0)
            serial.assert_not_called()
        with patch.object(self.engine.virtual_input, 'start'):
            self.board.sendto(next(packets(hello(), 3, 0)), self.destination)
            wait_for(self, lambda: session.steps['peer']['done'])
        self.assertEqual(session.build, 'a30c3ee3')
        now = session.last_state
        session.network_tick(now + 2.99)
        self.assertTrue(session.steps['peer']['done'])
        session.network_tick(now + 3)
        self.assertFalse(session.steps['peer']['done'])
        self.assertEqual(unpack(self.board.recv(65535))[3], b'\0')
        session.network_tick(now + 4.99)
        self.board.settimeout(.02)
        with self.assertRaises(socket.timeout):
            self.board.recv(65535)
        session.network_tick(now + 5)
        self.assertEqual(unpack(self.board.recv(65535))[3], b'\0')

    def test_timed_out_image_info_releases_command_for_next_folder(self):
        tool = self.eth.showcase
        payload = struct.pack('<HHH2x', 1, 1, 5) + b'a.png'
        with patch('tools.debug_tool.core.showcase.RESPONSE_TIMEOUT', .01):
            with self.assertRaisesRegex(TimeoutError, '命令应答超时'):
                tool.command_wait(IMAGE_INFO, payload, self.board.getsockname())
        _, expired_seq, _ = self.request()
        self.assertNotIn(IMAGE_INFO, tool.pending)
        command = tool.command(IMAGE_INFO, payload)
        self.assertEqual(self.request(), (IMAGE_INFO, command['seq'], payload))
        self.reply(ACK, expired_seq, struct.pack('<HBB', IMAGE_INFO, 1, 0))
        self.reply(ACK, expired_seq, struct.pack('<HBB', IMAGE_INFO, 2, 0))
        self.reply(ACK, command['seq'], struct.pack('<HBB', IMAGE_INFO, 2, 0))
        wait_for(self, lambda: IMAGE_INFO not in tool.pending)
        self.assertIsNone(self.eth.status()['rx']['error'])

    def test_every_command_ack_and_latest_detect(self):
        tool = self.eth.showcase
        payloads = {APP: struct.pack('<BBH', 1, 0, 0),
                    IMAGE_INFO: struct.pack('<HHH2x', 1, 1, 5) + b'a.png',
                    CHAIN: pack_chain(preset(1)), PRESET: struct.pack('<B3x', 1), DETECT: struct.pack('<B3x3I', 50, 1, 2, 4),
                    CANCEL: b''}
        for kind, payload in payloads.items():
            for phase in (2, 3):
                with self.subTest(kind=kind, phase=phase):
                    command = tool.command(kind, payload)
                    self.assertEqual(self.request(), (kind, command['seq'], payload))
                    self.reply(ACK, command['seq'], struct.pack('<HBB', kind, 1, 0))
                    wait_for(self, lambda: command['phase'] == 1)
                    if kind == DETECT:
                        tool.command(kind, payload)
                        latest_payload = struct.pack('<B3x3I', 89, 5, 6, 7)
                        tool.command(kind, latest_payload)
                        self.assertEqual(len(tool.latest), 1)
                    else:
                        with self.assertRaisesRegex(RuntimeError, '同类命令'):
                            tool.command(kind, payload)
                    self.reply(ACK, command['seq'], struct.pack('<HBB', kind, phase,
                                                               2 if phase == 3 else 0))
                    self.assertTrue(command['event'].wait(1))
                    if kind == DETECT:
                        next_kind, seq, data = self.request()
                        self.assertEqual((next_kind, data), (kind, latest_payload))
                        self.reply(ACK, seq, struct.pack('<HBB', kind, 2, 0))
                        wait_for(self, lambda: kind not in tool.pending)
                    self.assertNotIn(kind, tool.pending)

    def test_model_not_loaded_error_is_displayed(self):
        tool = self.eth.showcase
        command = tool.command(APP, struct.pack('<BBH', 1, 0, 0))
        kind, seq, _ = self.request()
        self.reply(ACK, seq, struct.pack('<HBB', kind, 3, 7))
        wait_for(self, lambda: self.engine.board.error is not None)
        self.assertTrue(command['event'].is_set())
        self.assertEqual(command['error'], 7)
        self.assertIn('未加载模型', self.engine.board.error)

    def test_model_not_loaded_state_is_displayed(self):
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        console = SocConsole(self.engine, Mock())
        self.addCleanup(console.close)
        console.video_timer.stop()
        payload = bytearray(state_payload(app=1, state=5))
        payload[2] = 7
        self.reply(STATE, 0, payload)
        wait_for(self, lambda: self.engine.board.board_state['error'] == 7)
        app.processEvents()
        self.assertIn('未加载模型', console.phase.text())

    def test_state_and_chain_updates_ui_without_refresh_timer(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        console = SocConsole(self.engine, Mock())
        self.addCleanup(console.close)
        self.reply(STATE, 0, state_payload(state=3, threshold=72, chain_rev=31))
        self.reply(CHAIN_STATE, 0, struct.pack('<I', 31) + pack_chain(preset(3)))
        wait_for(self, lambda: self.engine.board.chain_rev == 31)
        app.processEvents()
        self.assertEqual(console.app_choice.currentData(), 1)
        self.assertIn('已暂停', console.phase.text())
        self.assertEqual(console.detect_threshold.value(), 72)
        self.assertEqual(self.engine.board.board_state['chain_rev'], 31)
        self.assertEqual(console.pipeline.chain.count(), 3)
        self.assertEqual(console.pipeline.chain.item(0).data(256)['type'], 7)

    def test_image_step_uses_local_list_immediately(self):
        yolo = self.engine.yolo
        yolo.images = [Path('a.png'), Path('b.png'), Path('c.png')]
        yolo.image_index = 1
        yolo.image_destination = ('127.0.0.1', 5000, 6000)
        with patch.object(yolo, 'send_image') as send:
            self.reply(IMAGE_STEP, 0, struct.pack('<b3x', 1))
            wait_for(self, lambda: send.call_count == 1)
            send.assert_called_with(Path('c.png'), '127.0.0.1', 5000, 6000)
            self.reply(IMAGE_STEP, 0, struct.pack('<b3x', -1))
            wait_for(self, lambda: send.call_count == 2)
            send.assert_called_with(Path('b.png'), '127.0.0.1', 5000, 6000)

    def test_image_step_in_progress_is_ignored_without_queue(self):
        self.engine.yolo.capture_pending = True
        with patch.object(self.engine.yolo, 'send_image') as send:
            self.reply(IMAGE_STEP, 0, struct.pack('<b3x', 1))
            wait_for(self, lambda: any('当前图片未完成，忽略翻页' in entry['text']
                                       for entry in self.engine.get_entries()[0]))
            send.assert_not_called()

    def test_folder_selection_waits_for_manual_send_and_keeps_sorted_list(self):
        from tempfile import TemporaryDirectory
        from PySide6.QtGui import QImage
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        console = SocConsole(self.engine, Mock())
        self.addCleanup(console.close)
        with TemporaryDirectory() as directory:
            image = QImage(33, 17, QImage.Format_RGB888)
            image.fill('green')
            for name in ('b.png', 'a.png'):
                self.assertTrue(image.save(str(Path(directory) / name)))
            with (patch('gui.soc_console.QFileDialog.getExistingDirectory',
                        return_value=directory),
                  patch.object(self.engine.yolo, 'send_image') as send):
                console._choose_folder()
                send.assert_not_called()
                self.assertEqual([p.name for p in self.engine.yolo.images], ['a.png', 'b.png'])
                self.assertEqual(Path(console.image_path.text()).name, 'a.png')
                self.assertEqual(console.static_image.size().width(), 33)
                console.refresh()
                self.assertFalse(console.previous_image.isEnabled())
                self.assertTrue(console.next_image.isEnabled())
                self.engine.yolo.capture_pending = True
                console.refresh()
                self.assertFalse(console.next_image.isEnabled())
                send.assert_not_called()
        app.processEvents()

    def test_rest_and_cli_send_chain_without_serial(self):
        import json
        import subprocess
        import urllib.request
        from tools.debug_tool.core.api import ApiServer
        api = ApiServer(self.engine, port=0)
        api.start()
        self.addCleanup(api.stop)
        url = f'http://127.0.0.1:{api._httpd.server_port}'
        body = preset(5)
        request = urllib.request.Request(url + '/api/pipeline', data=json.dumps(body).encode(),
                                         headers={'Content-Type': 'application/json'})
        with patch.object(self.engine, 'send') as serial:
            with urllib.request.urlopen(request, timeout=2) as response:
                self.assertEqual(response.status, 200)
            kind, seq, payload = self.request()
            self.assertEqual((kind, payload), (CHAIN, pack_chain(body)))
            self.reply(ACK, seq, struct.pack('<HBB', CHAIN, 2, 0))
            wait_for(self, lambda: CHAIN not in self.eth.showcase.pending)
            result = subprocess.run([sys.executable, 'tools/debug_tool/cli.py', '--url', url,
                                     'pipeline', json.dumps(preset(3))],
                                    capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            kind, seq, payload = self.request()
            self.assertEqual(unpack_chain(payload), preset(3))
            self.reply(ACK, seq, struct.pack('<HBB', CHAIN, 2, 0))
            serial.assert_not_called()
