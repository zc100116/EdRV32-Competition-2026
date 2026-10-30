"""test_session.py — SoC console design 4.2–4.3, shared UDP and REST; host only.

Exercise real datagrams through one 6000 listener and serial status parsing.
Qt checks cover both required sizes and each project's disabled controls.
"""

import json
import os
from pathlib import Path
import socket
import sys
import time
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
import urllib.request

from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.ethernet import HEADER, packets
from tools.debug_tool.core.session import PROJECTS
from tools.debug_tool.core.yolo import INPUT_BYTES, OUTPUT_BYTES
from test_program import wait_for
from test_telemetry import wire
from test_video import detection_wire, frame_header


class SessionTest(unittest.TestCase):
    def setUp(self):
        self.engine = SerialEngine()
        self.addCleanup(self.engine.ethernet.stop_receive)

    def test_phase_follows_serial_lines_and_disconnect(self):
        self.assertEqual(self.engine.board.status()['phase'], 'disconnected')
        for line, phase in [('BIOS menu: 1=Program SRAM', 'bios'),
                            ('Demo: demo_vision', 'application'),
                            ('Switch: frames=2 mtime_ticks=30', 'application'),
                            ('BIOS menu: 1=Program SRAM', 'bios'),
                            ('Demo: demo_vnpu', 'application'),
                            ('BIOS menu: 1=Program SRAM', 'bios'),
                            ('RND display ready', 'application')]:
            self.engine._match_line(line)
            self.assertEqual(self.engine.board.status()['phase'], phase)
        self.engine.disconnect()
        self.assertEqual(self.engine.board.status()['phase'], 'disconnected')

    def test_four_project_capability_tables(self):
        expected = {'B3V': (True, True, False, True),
                    'B3VN': (True, True, True, True),
                    'B3R': (True, False, False, False),
                    'B3F': (True, True, True, True)}
        for name, values in expected.items():
            with self.subTest(project=name):
                state = self.engine.board.select_project(name)
                self.assertEqual(state['project'], name)
                self.assertEqual(tuple(state['capabilities'][key] for key in
                                       ('program', 'processing', 'detection', 'network')), values)
                if not all(values):
                    self.assertIn(name, state['capabilities']['reason'])

    def test_network_sequence_peer_match_and_independent_data_counts(self):
        board = self.engine.board
        with (TemporaryDirectory() as directory,
              socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer):
            peer.bind(('127.0.0.1', 0))
            peer.settimeout(2)
            self.engine.ethernet.start_receive(6000, directory, mode='console')
            def status_command(text, ending):
                # The WIN3 must already be on the wire when UART status is sent.
                self.assertEqual(text, 'status')
                self.assertEqual(ending, 'cr')
                packet, source = peer.recvfrom(1024)
                self.assertEqual(packet, HEADER.pack(3, 1, 0, 0) + b'\0')
                self.assertEqual(source, ('127.0.0.1', 6000))
            with patch.object(self.engine, 'send', side_effect=status_command):
                state = board.establish_network('127.0.0.1', peer.getsockname()[1])
            self.assertEqual([state['network'][key]['done'] for key in
                              ('listen', 'win3', 'peer', 'data')], [True, True, False, False])
            self.assertEqual(state['expectedPeer'], ['127.0.0.1', 6000])
            self.engine._match_line('ETH peer IP: 0x7f000001')
            self.engine._match_line('ETH peer port: 6001')
            self.assertFalse(board.status()['network']['peer']['done'])
            self.assertIn('不一致', board.status()['error'])
            # A new explicit setup requires a fresh pair of status fields.
            with patch.object(self.engine, 'send', side_effect=status_command):
                board.establish_network('127.0.0.1', peer.getsockname()[1])
            self.engine._match_line('ETH peer IP: 0x7f000001')
            self.engine._match_line('ETH peer port: 6000')
            peer.sendto(next(packets(wire(1), 3, 0)), ('127.0.0.1', 6000))
            wait_for(self, lambda: board.status()['counts']['telemetry'] == 1)
            state = board.status()
            self.assertTrue(all(step['done'] for step in state['network'].values()))
            self.assertEqual(state['counts']['video'], 0)
            self.assertTrue(all(step['time'] for step in state['network'].values()))
            self.engine.ethernet.stop_receive()
            self.assertFalse(board.status()['network']['listen']['done'])

    def test_video_monitor_yolo_and_files_bind_6000_once(self):
        binds = []
        original_socket = socket.socket
        class CountingSocket(original_socket):
            def bind(self, address):
                binds.append(address)
                return super().bind(address)
        with (TemporaryDirectory() as directory,
              patch('tools.debug_tool.core.ethernet.socket.socket', CountingSocket)):
            self.engine.ethernet.start_receive(6000, directory, mode='console')
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as source:
                destination = ('127.0.0.1', 6000)
                def send(window, data, notify=True):
                    for packet in packets(data, window, 0):
                        if not notify:
                            packet = packet[:1] + b'\0' + packet[2:]
                        source.sendto(packet, destination)
                        # Pace the large raw return to exercise the real receive thread.
                        time.sleep(.0002)
                send(2, detection_wire())
                send(0, frame_header() + bytes(1280))
                send(3, wire(1))
                wait_for(self, lambda: self.engine.video.snapshot()['received'] == 1)
                self.engine.yolo.reset_capture()
                # Camera traffic can still arrive while the test image is uploading.
                send(2, detection_wire(10))
                send(0, frame_header(10) + bytes(1280))
                wait_for(self, lambda: self.engine.video.snapshot()['received'] == 2)
                self.assertIsNone(self.engine.yolo.snapshot()[1])
                send(0, bytes(INPUT_BYTES), False)
                send(3, wire(2))
                send(1, bytes(OUTPUT_BYTES), False)
                send(2, detection_wire())
                wait_for(self, lambda: self.engine.yolo.snapshot()[1] is not None)
                send(0, frame_header(11) + bytes(1280))
                send(1, b'file receive')
                send(0, b'generic WIN0 file')
                send(3, wire(3))
                wait_for(self, lambda: self.engine.video.snapshot()['received'] == 3)
                wait_for(self, lambda: self.engine.telemetry.status()['records'] == 3)
            self.engine.ethernet.stop_receive()
            self.assertEqual(binds, [('', 6000)])
            self.assertEqual(self.engine.video.snapshot()['frame'].frame_id, 11)
            self.assertEqual(self.engine.yolo.snapshot()[1][2].frame_id, 9)
            self.assertEqual(self.engine.telemetry.status()['records'], 3)
            self.assertIsNone(self.engine.ethernet.status()['rx']['error'])
            self.assertEqual((Path(directory) / 'window1.bin').read_bytes()[:12], b'file receive')
            self.assertEqual((Path(directory) / 'window0.bin').read_bytes()[:17],
                             b'generic WIN0 file')

    def test_network_failure_is_visible_and_logged(self):
        with patch.object(self.engine.ethernet, 'start_receive', side_effect=OSError('busy 6000')):
            with self.assertRaisesRegex(OSError, 'busy 6000'):
                self.engine.board.establish_network()
        self.assertIn('busy 6000', self.engine.board.status()['error'])
        self.assertIn('busy 6000', self.engine.get_entries()[0][-1]['text'])

    def test_rest_new_state_and_original_status_share_session(self):
        api = ApiServer(self.engine, port=0)
        api.start()
        self.addCleanup(api.stop)
        url = f'http://127.0.0.1:{api._httpd.server_port}'
        def request(path, body=None):
            req = urllib.request.Request(url + path, data=None if body is None else
                                         json.dumps(body).encode(),
                                         headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=3) as response:
                return json.load(response)
        self.assertEqual(request('/api/board')['project'], 'B3V')
        request('/api/board/project', {'project': 'B3F'})
        self.engine._match_line('Demo: demo')
        self.engine._match_line('Scene: 1')
        self.engine._match_line('Monitor Hz: 100')
        board = request('/api/board')
        self.assertEqual(request('/api/status')['board'], board)
        self.assertEqual(board['phase'], 'application')
        self.assertEqual(board['project'], 'B3F')
        self.assertEqual(board['summary'], {'Scene': '1', 'Monitor Hz': '100'})
        with (socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer,
              patch.object(self.engine, 'send') as send):
            peer.bind(('127.0.0.1', 0))
            self.engine.ethernet.start_receive(0, mode='files')
            state = request('/api/board/network', {'boardIp': '127.0.0.1',
                                                  'boardPort': peer.getsockname()[1]})
            send.assert_called_once_with('status', 'cr')
            self.assertTrue(state['network']['win3']['done'])
            self.assertEqual(request('/api/ethernet/status')['rx']['localPort'], 6000)


class ConsoleLayoutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from PySide6.QtWidgets import QApplication
        cls.app = QApplication.instance() or QApplication([])

    def test_two_window_sizes_and_capabilities(self):
        from PySide6.QtWidgets import QLabel
        from gui.app import MainWindow
        engine = SerialEngine()
        window = MainWindow(engine)
        from PySide6.QtCore import Qt, QCoreApplication, QEvent
        window.setAttribute(Qt.WA_DeleteOnClose)
        def cleanup():
            window.close()
            QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
            self.app.processEvents()
        self.addCleanup(cleanup)
        window.show()
        for width, height in ((1366, 768), (1920, 1080)):
            window.resize(width, height)
            self.app.processEvents()
            self.assertEqual((window.width(), window.height()), (width, height))
            console = window.soc
            for name, caps in PROJECTS.items():
                console.project.setCurrentText(name)
                console.refresh()
                self.app.processEvents()
                self.assertEqual(console.send_model.isEnabled(), caps['detection'])
                self.assertEqual(console.apply_scene.isEnabled(), caps['processing'])
                self.assertEqual(console.establish.isEnabled(), caps['network'])
                if not caps['detection']:
                    self.assertIn(name, console.model_note.text())
                    self.assertIn(name, console.image_note.text())
                # Titles and single-line status fields must fit their complete text.
                for widget in console.findChildren(QLabel):
                    if widget.property('role') == 'title':
                        self.assertGreaterEqual(widget.width(),
                                                widget.fontMetrics().horizontalAdvance(
                                                    widget.text()))
        self.assertEqual(len(window.rail_group.buttons()), 5)
        self.assertFalse(hasattr(window, 'video'))
