"""test_session.py — SoC console design 4.2–4.3, shared UDP and REST; host only.

Exercise real datagrams through one 6000 listener and serial status parsing.
Qt checks cover every page and parameter text at both required sizes.
"""

import json
import os
from pathlib import Path
import socket
import sys
import time
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch
import urllib.request

from tools.debug_tool.core.api import ApiServer
from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.ethernet import HEADER, packets
from tools.debug_tool.core.yolo import INPUT_BYTES, OUTPUT_BYTES
from test_program import wait_for
from test_telemetry import wire
from test_video import detection_wire, frame_header


class SessionTest(unittest.TestCase):
    def setUp(self):
        ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                      return_value=('loopback', 0.0))
        ready.start()
        self.addCleanup(ready.stop)
        self.engine = SerialEngine()
        # Phase/parser tests do not own a UDP board; discovery is tested below.
        self.engine.board.network_endpoint = ('', 5000)
        self.engine.ethernet.local_ip = "127.0.0.1"
        self.addCleanup(self.engine.ethernet.stop_receive)

    def test_phase_follows_serial_lines_and_disconnect(self):
        self.assertEqual(self.engine.board.status()['phase'], 'disconnected')
        for line, phase in [('BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud', 'bios'),
                            ('Demo: demo_vision', 'application'),
                            ('Switch: frames=2 mtime_ticks=30', 'application'),
                            ('BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud', 'bios'),
                            ('Demo: demo_vnpu', 'application'),
                            ('BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud', 'bios'),
                            ('RND display ready', 'application')]:
            self.engine._match_line(line)
            self.assertEqual(self.engine.board.status()['phase'], phase)
        self.engine.disconnect()
        self.assertEqual(self.engine.board.status()['phase'], 'disconnected')

    def test_no_project_selection_or_capability_filter(self):
        state = self.engine.board.status()
        self.assertNotIn('project', state)
        self.assertNotIn('capabilities', state)
        self.assertFalse(hasattr(self.engine.board, 'select_project'))

    def test_network_sequence_peer_match_and_independent_data_counts(self):
        board = self.engine.board
        with (TemporaryDirectory() as directory,
              socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer):
            peer.bind(('127.0.0.1', 0))
            peer.settimeout(2)
            self.engine.ethernet.start_receive(6000, directory, mode='console')
            with patch.object(self.engine, 'send') as send:
                state = board.establish_network('127.0.0.1', peer.getsockname()[1])
                send.assert_not_called()
            packet, source = peer.recvfrom(1024)
            self.assertEqual(packet, HEADER.pack(3, 1, 0, 0) + b'\0')
            self.assertEqual(source, ('127.0.0.1', 6000))
            self.assertEqual([state['network'][key]['done'] for key in
                              ('listen', 'win3', 'peer', 'data')], [True, True, False, False])
            self.assertEqual(state['expectedPeer'], ['127.0.0.1', 6000])
            self.engine._match_line('ETH peer IP: 0x7f000001')
            self.engine._match_line('ETH peer port: 6001')
            self.assertFalse(board.status()['network']['peer']['done'])
            self.assertIn('不一致', board.status()['error'])
            # A new explicit setup requires a fresh pair of status fields.
            with patch.object(self.engine, 'send') as send:
                board.establish_network('127.0.0.1', peer.getsockname()[1])
                send.assert_not_called()
            self.assertEqual(peer.recvfrom(1024)[0], HEADER.pack(3, 1, 0, 0) + b'\0')
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
        original_socket = socket.socket
        with (TemporaryDirectory() as directory,
              patch('tools.debug_tool.core.ethernet.socket.socket',
                    side_effect=original_socket) as factory):
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
            datagram_sockets = [call for call in factory.call_args_list
                                if call.args == (socket.AF_INET, socket.SOCK_DGRAM)]
            # One shared listener and the test's sender; spawn must receive a real socket.
            self.assertEqual(len(datagram_sockets), 2)
            self.assertEqual(self.engine.video.snapshot()['frame'].frame_id, 11)
            self.assertEqual(self.engine.yolo.snapshot()[1][2].frame_id, 9)
            self.assertEqual(self.engine.telemetry.status()['records'], 3)
            self.assertIsNone(self.engine.ethernet.status()['rx']['error'])
            self.assertEqual((Path(directory) / 'window1.bin').read_bytes()[:12], b'file receive')
            self.assertEqual((Path(directory) / 'window0.bin').read_bytes()[:17],
                             b'generic WIN0 file')

    def test_configured_address_is_expected_peer_and_source(self):
        with (TemporaryDirectory() as directory,
              socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer):
            peer.bind(('127.0.0.1', 0))
            peer.settimeout(2)
            self.engine.ethernet.start_receive(6000, directory, mode='console')
            state = self.engine.board.establish_network(
                '127.0.0.1', peer.getsockname()[1], '127.0.0.2')
            _, source = peer.recvfrom(1024)
            self.assertEqual(source, ('127.0.0.2', 6000))
            self.assertEqual(state['expectedPeer'], ['127.0.0.2', 6000])
            self.assertEqual(self.engine.ethernet.status()['rx']['localIp'], '127.0.0.2')

    def test_real_bind_failure_is_visible_without_fallback(self):
        with (socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as occupied,
              patch('tools.debug_tool.core.ethernet.socket.socket', wraps=socket.socket)
              as factory):
            occupied.bind(('127.0.0.1', 6000))
            with self.assertRaisesRegex(OSError, 'UDP bind 127.0.0.1:6000'):
                self.engine.board.establish_network(local_ip='127.0.0.1')
            self.assertEqual(factory.call_count, 1)
            self.assertIn('UDP bind 127.0.0.1:6000', self.engine.board.status()['error'])
            self.assertFalse(self.engine.ethernet.status()['rx']['active'])

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
        self.assertNotIn('project', request('/api/board'))
        self.engine._match_line('Demo: demo')
        self.engine._match_line('Scene: 1')
        self.engine._match_line('Monitor Hz: 100')
        board = request('/api/board')
        self.assertEqual(request('/api/status')['board'], board)
        self.assertEqual(board['phase'], 'application')
        self.assertEqual(board['summary'], {'Scene': '1', 'Monitor Hz': '100'})
        with (socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer,
              patch.object(self.engine, 'send') as send):
            peer.bind(('127.0.0.1', 0))
            self.engine.ethernet.start_receive(0, mode='files')
            state = request('/api/board/network', {'boardIp': '127.0.0.1',
                                                  'boardPort': peer.getsockname()[1],
                                                  'localIp': '127.0.0.2'})
            send.assert_not_called()
            self.assertTrue(state['network']['win3']['done'])
            self.assertEqual(state['expectedPeer'], ['127.0.0.2', 6000])
            self.assertEqual(request('/api/ethernet/status')['rx']['localPort'], 6000)


class DiscoveryTest(unittest.TestCase):
    def setUp(self):
        self.engine = SerialEngine()
        self.board = self.engine.board
        self.tool = self.engine.ethernet
        self.tool.rx_socket = Mock()
        self.tool.rx.update(active=True, localIp=self.tool.local_ip, localPort=6000)
        self.clock = 0.0
        self.sent = []
        self.tool.rx_socket.sendto.side_effect = lambda *args: self.sent.append(
            (self.clock, args))
        self.thread_patch = patch('tools.debug_tool.core.session.threading.Thread')
        self.thread = self.thread_patch.start()
        self.addCleanup(self.thread_patch.stop)
        self.ready = patch.object(self.tool, 'wait_for_link')
        self.wait_ready = self.ready.start()
        self.addCleanup(self.ready.stop)

    def enter(self, line='Showcase: main menu'):
        self.board.feed_line(line)
        self.assertEqual(self.board.phase, 'application')
        self.thread.return_value.start.assert_called_once()
        self.stop = self.board.discovery_stop

    def run_clock(self, on_wait):
        def wait(seconds):
            self.assertEqual(seconds, 2.0)
            if not self.stop.is_set():
                self.clock += seconds
                on_wait()
            return self.stop.is_set()
        with patch.object(self.stop, 'wait', side_effect=wait):
            self.board._discover_network(self.stop)

    def test_enter_requests_every_two_seconds_until_peer(self):
        self.enter()
        self.board.feed_line('Showcase: another status')
        self.thread.return_value.start.assert_called_once()
        def reply():
            if self.clock == 2:
                self.board.feed_line('ETH peer IP: 0xc0a80102')
            if self.clock == 6:
                self.board.feed_line('ETH peer port: 6000')
        self.run_clock(reply)
        self.assertEqual([item[0] for item in self.sent], [0, 2, 4])
        self.assertTrue(self.board.steps['peer']['done'])
        expected = (next(packets(b'\0', 3, 0)), self.board.network_endpoint)
        self.assertTrue(all(args == expected for _, args in self.sent))
        self.assertEqual(self.wait_ready.call_count, 3)
        logs = self.engine.get_entries()[0]
        self.assertEqual(sum('连接请求已发送' in item['text'] for item in logs), 3)

    def test_bios_returns_input_to_serial_and_application_restarts_discovery(self):
        from tools.debug_tool.core.virtual_input import channel
        self.enter('Demo: demo')
        def bios():
            self.board.mark('peer')
            self.assertEqual(channel(self.engine), '网口')
            self.board.feed_line('BIOS menu: 1=UART load')
        self.run_clock(bios)
        self.assertEqual(channel(self.engine), '串口')
        self.assertEqual(len(self.sent), 1)
        previous = self.stop
        self.thread.reset_mock()
        self.enter()
        self.assertIsNot(self.stop, previous)
        self.run_clock(self.board.disconnect)
        self.assertEqual(len(self.sent), 2)

    def test_disconnect_while_waiting_for_link_sends_nothing(self):
        self.enter()
        self.wait_ready.side_effect = lambda ip: self.board.disconnect()
        self.run_clock(lambda: self.fail('cancelled discovery waited again'))
        self.assertEqual(self.sent, [])

    def test_send_failure_is_logged_and_not_retried(self):
        self.enter()
        self.tool.rx_socket.sendto.side_effect = OSError('send failed')
        self.run_clock(lambda: self.fail('failed discovery retried'))
        self.tool.rx_socket.sendto.assert_called_once()
        self.assertIn('send failed', self.board.status()['error'])

    def test_no_configured_board_address_does_not_start_discovery(self):
        self.board.network_endpoint = ('', 5000)
        self.board.feed_line('Showcase: main menu')
        self.assertEqual(self.board.phase, 'application')
        self.thread.assert_not_called()


class ConsoleLayoutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from PySide6.QtWidgets import QApplication
        cls.app = QApplication.instance() or QApplication([])

    def test_all_pages_at_both_sizes(self):
        from PySide6.QtCore import QPoint, QRect
        from PySide6.QtWidgets import QLabel, QPushButton, QCheckBox, QGroupBox, QAbstractSpinBox, QComboBox, QWidget
        from gui.app import MainWindow
        window = MainWindow(SerialEngine())
        for panel in (window.soc, window.ethernet, window.virtual_input):
            self.assertEqual(panel.local_ip.text(), "192.168.1.2")
        self.addCleanup(window.close)
        window.show()
        for width, height in ((1366, 768), (1920, 1080)):
            window.resize(width, height)
            for page in range(5):
                window._select_page(page)
                for subpage in range(3) if page == 4 else [0]:
                    window.soc.pages.setCurrentIndex(subpage)
                    self.app.processEvents()
                    self.assertEqual((window.width(), window.height()), (width, height))
                    for widget in window.findChildren(QLabel):
                        if widget.isVisible() and widget.text() and '<' not in widget.text():
                            if widget.wordWrap():
                                needed = widget.heightForWidth(widget.width())
                                self.assertGreaterEqual(widget.height(), needed,
                                    f'{width}x{height}: {widget.text()!r}')
                            else:
                                self.assertTrue(widget.toolTip() or widget.width() >=
                                    widget.fontMetrics().horizontalAdvance(widget.text()),
                                    f'{width}x{height}: {widget.text()!r}')
                    for widget in window.findChildren(QPushButton):
                        if widget.isVisible():
                            self.assertTrue(widget.toolTip() or widget.width() >=
                                widget.fontMetrics().horizontalAdvance(widget.text()) + 8,
                                widget.text())
                    for widget in window.soc.findChildren(QLabel) + window.soc.findChildren(
                            QCheckBox) + window.soc.findChildren(QGroupBox):
                        text = widget.title() if isinstance(widget, QGroupBox) else widget.text()
                        self.assertNotRegex(text, r'B3(?:R|N|V|VN|F)|WIN[0-3]|窗口号')
                    self.assertFalse(hasattr(window.soc, 'project'))
                    if page == 4:
                        scroll = window.soc.pages.currentWidget()
                        fields = scroll.widget().findChildren(QWidget)
                        types = (QLabel, QPushButton, QCheckBox, QComboBox, QAbstractSpinBox)
                        for field in fields:
                            if isinstance(field, types) and field.isVisible():
                                scroll.ensureWidgetVisible(field, 0, 0)
                                self.app.processEvents()
                                bounds = QRect(field.mapTo(scroll.viewport(), QPoint()), field.size())
                                self.assertTrue(scroll.viewport().rect().contains(bounds),
                                    f'{width}x{height}: inaccessible {field.objectName()}')
                    if page == 2:
                        for row in window.rules._rows:
                            self.assertLessEqual(row.width(), row.parentWidget().width())
                            for button in row.findChildren(QPushButton):
                                self.assertTrue(row.rect().contains(button.geometry()))
                    for spin in window.soc.processing.findChildren(QAbstractSpinBox):
                        editor = spin.lineEdit()
                        self.assertGreaterEqual(editor.width(),
                            editor.fontMetrics().horizontalAdvance(editor.text()) + 4)
            console = window.soc
            self.assertTrue(console.processing.lock_scale.isChecked())
            self.assertTrue(console.choose_folder.isEnabled())
            self.assertTrue(console.apply_output.isEnabled())
            self.assertTrue(console.status_query.isEnabled())
            last = console.table.visualItemRect(console.table.item(6, 3))
            self.assertLess(last.bottom(), console.table.viewport().height())
            self.assertEqual(console.table.verticalScrollBar().maximum(), 0)
