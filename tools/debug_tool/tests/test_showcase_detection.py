"""Image BULK regressions for showcase design 4.5.4/4.5.9; host clock domain.
Exercise Qt selection/preview and real UDP uploads, delayed returns and DONE.
"""
import os
from pathlib import Path
import socket
import struct
import sys
from tempfile import TemporaryDirectory
import time
import unittest
from unittest.mock import Mock, patch

from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.ethernet import packets, unpack
from tools.debug_tool.core.showcase import (
    BULK_BEGIN, READY, DONE, APP, IMAGE_INFO, ACK, decode, encode,
)
from tools.debug_tool.core.yolo import INPUT_BYTES, OUTPUT_BYTES, image_rgb565
from test_program import wait_for

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


class ShowcaseDetectionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtWidgets import QApplication
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        from gui.soc_console import SocConsole
        from PySide6.QtGui import QImage
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = SerialEngine()
        self.addCleanup(self.engine.virtual_input.close)
        self.eth = self.engine.ethernet
        self.eth.local_ip = '127.0.0.1'
        self.addCleanup(self.eth.stop_receive)
        self.eth.start_receive(0, self.directory.name, mode='console')
        self.board = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.board.bind(('127.0.0.1', 0))
        self.board.settimeout(5)
        self.addCleanup(self.board.close)
        self.console = SocConsole(self.engine, Mock())
        self.addCleanup(self.console.close)
        self.console.local_ip.setText('127.0.0.1')
        self.console.ip.setText('127.0.0.1')
        self.paths = []
        for name, color in (('a', 'red'), ('b', 'blue')):
            path = Path(self.directory.name) / f'{name}.png'
            image = QImage(13, 7, QImage.Format_RGB888)
            image.fill(color)
            self.assertTrue(image.save(str(path)))
            self.paths.append(str(path))
        ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                      return_value=('loopback', 0.0))
        ready.start()
        self.addCleanup(ready.stop)
        listen = patch.object(self.eth, 'listen_console')
        listen.start()
        self.addCleanup(listen.stop)
        send_image = self.engine.yolo.send_image
        send = patch.object(self.engine.yolo, 'send_image', side_effect=lambda path, *_:
                            send_image(path, '127.0.0.1', self.board.getsockname()[1],
                                       self.eth.rx_socket.getsockname()[1]))
        send.start()
        self.addCleanup(send.stop)

        def paced(data, window, offset):
            for packet in packets(data, window, offset):
                time.sleep(.0002)
                yield packet
        pacing = patch('tools.debug_tool.core.ethernet.packets', paced)
        pacing.start()
        self.addCleanup(pacing.stop)

    def choose(self, path):
        with patch('gui.soc_console.QFileDialog.getOpenFileName', return_value=(path, '')):
            self.console._choose_image()
        # Refresh used to replace the new selection/preview with the last sent image.
        for _ in range(3):
            self.console.refresh()
            self.app.processEvents()
        self.assertEqual(self.console.image_path.text(), path)
        self.assertEqual(self.console.loaded_image, path)

    def upload(self):
        self.console._send_image()
        packet, self.peer = self.board.recvfrom(65535)
        kind, self.seq, payload = decode(unpack(packet)[3])
        if kind == APP:
            self.assertEqual(payload, struct.pack('<BBH', 2, 0, 0))
            self.reply(ACK, struct.pack('<HBB', APP, 1, 0))
            self.reply(ACK, struct.pack('<HBB', APP, 2, 0))
            packet, self.peer = self.board.recvfrom(65535)
            kind, self.seq, payload = decode(unpack(packet)[3])
        self.assertEqual(kind, IMAGE_INFO)
        self.assertEqual(struct.unpack_from('<HH', payload), (1, 1))
        self.assertEqual(payload[8:].decode(), Path(self.console.image_path.text()).name)
        self.reply(ACK, struct.pack('<HBB', IMAGE_INFO, 2, 0))
        packet, self.peer = self.board.recvfrom(65535)
        kind, self.seq, payload = decode(unpack(packet)[3])
        self.assertEqual((kind, payload), (BULK_BEGIN, struct.pack('<B3xI', 2, 1843200)))
        self.reply(READY, struct.pack('<B3x', 2))
        received = bytearray()
        while True:
            window, notify, offset, data = unpack(self.board.recv(65535))
            self.assertEqual((window, offset), (0, len(received)))
            received.extend(data)
            if notify:
                break
        return bytes(received)

    def reply(self, kind, payload):
        self.board.sendto(next(packets(encode(kind, self.seq, payload), 3, 0)), self.peer)

    def return_result(self):
        boxes = ((20, 30, 100, 200, 15, 900),)
        detection = struct.pack('<4sHHII6H', b'EDDT', 1, 1, 7, self.seq, *boxes[0])
        for window, data in enumerate((bytes(INPUT_BYTES), bytes(4), detection)):
            for packet in packets(data, window, 0):
                self.board.sendto(packet, self.peer)
                time.sleep(.0002)
        wait_for(self, lambda: self.engine.yolo.snapshot()[1] is not None)
        return boxes

    def done(self, status=0):
        self.reply(DONE, struct.pack('<BB2xI', 2, status, 7))
        wait_for(self, lambda: not self.eth.status()['tx']['active'])
        self.console.refresh()

    def test_three_second_return_waits_for_done_without_auto_advance(self):
        self.choose(self.paths[0])
        self.assertEqual(self.upload(), image_rgb565(self.paths[0]))
        from PySide6.QtTest import QTest
        QTest.qWait(3000)
        self.assertTrue(self.engine.yolo.capture_pending)
        self.assertEqual(self.engine.yolo.failed, 0)
        boxes = self.return_result()
        with patch.object(self.engine.yolo, 'send_image') as next_image:
            self.console.refresh()
            self.assertTrue(self.engine.yolo.capture_pending)
            self.assertFalse(self.console.send_image.isEnabled())
            self.done()
            next_image.assert_not_called()
        self.console._display()
        from tools.debug_tool.core.yolo import original_boxes
        image = self.console.static_image
        self.assertEqual(self.console.view.boxes,
                         original_boxes(boxes, image.width(), image.height()))
        self.assertIn('回传完整', self.console.capture_status.text())
        self.assertIsNone(self.eth.status()['tx']['error'])
        self.assertGreaterEqual(self.engine.yolo.timings[0]['seconds'], 3)

    def test_choose_a_send_then_choose_b_sends_b_pixels_and_preview(self):
        for path, color in zip(self.paths, ('#ff0000', '#0000ff')):
            self.choose(path)
            self.assertEqual(self.console.static_image.pixelColor(0, 0).name(), color)
            self.assertEqual(self.upload(), image_rgb565(path))
            self.return_result()
            self.done()
            self.assertEqual(self.engine.yolo.source_image, path)
            self.assertIsNone(self.eth.status()['tx']['error'])

    def test_done_missing_return_rejection_and_timeout_fail_capture(self):
        for reason in ('missing', 'rejected', 'timeout'):
            with self.subTest(reason=reason):
                self.choose(self.paths[0])
                timeout = patch('tools.debug_tool.core.showcase.RESPONSE_TIMEOUT',
                                .8 if reason == 'timeout' else 5)
                with timeout:
                    self.upload()
                    if reason == 'timeout':
                        wait_for(self, lambda: not self.eth.status()['tx']['active'])
                        self.console.refresh()
                        text = '设备回复超时'
                    else:
                        if reason == 'rejected':
                            self.return_result()
                        self.done(2 if reason == 'rejected' else 0)
                        text = '格式错误' if reason == 'rejected' else '回传不完整'
                self.assertIn(text, self.engine.yolo.error)
                self.assertIn(text, self.console.capture_status.text())
                self.assertIn(text, self.eth.status()['tx']['error'])
                self.assertIsNone(self.engine.yolo.snapshot()[1])
                self.assertFalse(self.engine.yolo.capture_pending)

    def test_mismatched_request_is_discarded_then_current_result_completes(self):
        self.choose(self.paths[0])
        self.upload()
        stale = struct.pack('<4sHHII', b'EDDT', 1, 0, 99, self.seq + 1)
        for window, data in enumerate((bytes(INPUT_BYTES), bytes(4), stale)):
            for packet in packets(data, window, 0):
                self.board.sendto(packet, self.peer)
                time.sleep(.0002)
        time.sleep(.05)
        self.assertIsNone(self.engine.yolo.snapshot()[1])
        self.assertTrue(self.engine.yolo.capture_pending)
        self.return_result()
        self.reply(DONE, struct.pack('<BB2xI', 2, 0, 7))
        # No GUI refresh or Qt event pumping is involved in completion.
        wait_for(self, lambda: not self.eth.tx['active'])
        self.assertFalse(self.engine.yolo.capture_pending)
        self.assertEqual(self.engine.yolo.image_status, '完成')

    def test_cancel_ack_and_done_end_current_image_without_gui_timer(self):
        self.choose(self.paths[0])
        self.upload()
        bulk_seq = self.seq
        self.engine.board.network_endpoint = self.board.getsockname()
        command = self.eth.showcase.cancel()
        kind, seq, payload = decode(unpack(self.board.recv(65535))[3])
        from tools.debug_tool.core.showcase import CANCEL
        self.assertEqual((kind, seq, payload), (CANCEL, command['seq'], b''))
        self.seq = seq
        self.reply(ACK, struct.pack('<HBB', CANCEL, 2, 0))
        self.seq = bulk_seq
        self.reply(DONE, struct.pack('<BB2xI', 2, 6, 0))
        wait_for(self, lambda: not self.eth.tx['active'])
        self.assertTrue(command['event'].is_set())
        self.assertFalse(self.engine.yolo.capture_pending)
        self.assertIsNone(self.engine.yolo.snapshot()[1])
        self.assertIn('已取消', self.engine.yolo.error)
