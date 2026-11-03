"""test_showcase.py — design 4.5.3–4.5.5 wire protocol and game record vectors.
Local UDP board replies exercise the actual receive thread and transfer worker.
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

from tools.debug_tool.core.ethernet import EthernetTool, packets, unpack
from tools.debug_tool.core.showcase import (encode, decode, BULK_BEGIN, APP, ACK, ECHO,
                                             READY, DONE, ECHO_REPLY)
from tools.debug_tool.core.virtual_input import FRAME, VirtualInput, send_frame
from tools.sw.game_record import build_record, build_pack
from test_program import wait_for

ROOT = Path(__file__).resolve().parents[3]


class ShowcaseTest(unittest.TestCase):
    def setUp(self):
        self.ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                           return_value=('loopback', 0.0))
        self.ready.start()
        self.addCleanup(self.ready.stop)
        self.eth = EthernetTool(local_ip='127.0.0.1')
        self.addCleanup(self.eth.stop_receive)
        self.board = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.board.bind(('127.0.0.1', 0))
        self.board.settimeout(2)
        self.addCleanup(self.board.close)
        self.destination = ('127.0.0.1', self.board.getsockname()[1], 0)

    def request(self):
        packet, peer = self.board.recvfrom(65535)
        window, notify, offset, data = unpack(packet)
        self.assertEqual((window, notify, offset), (3, True, 0))
        return (*decode(data), peer)

    def reply(self, peer, kind, seq, payload=b''):
        self.board.sendto(next(packets(encode(kind, seq, payload), 3, 0)), peer)

    def test_edsc_exact_layout_and_errors(self):
        data = encode(BULK_BEGIN, 0x12345678, struct.pack('<B3xI', 3, 1234))
        self.assertEqual(data, bytes.fromhex('45445343010008007856341203000000d2040000'))
        self.assertEqual(decode(data), (1, 0x12345678, struct.pack('<B3xI', 3, 1234)))
        for kind, payload in ((READY, b'\x03\0\0\0'),
                              (DONE, struct.pack('<BB2xI', 3, 0, 30)),
                              (APP, struct.pack('<BBH', 1, 0, 0)),
                              (ECHO, bytes(1000)), (ECHO_REPLY, b'echo')):
            self.assertEqual(decode(encode(kind, 42, payload)), (kind, 42, payload))
        for invalid in (b'FAIL' + data[4:], data[:-1], data + b'0',
                        encode(READY, 1, b''), encode(0x99, 1)):
            with self.assertRaises(ValueError):
                decode(invalid)
        with self.assertRaises(ValueError):
            encode(ECHO, 1, bytes(1001))

    def test_bulk_waits_ready_then_done_and_allows_next_game(self):
        for kind, index in ((1, 0), (3, 30), (3, 31)):
            data = bytes(range(251)) * 11
            self.eth.showcase.bulk(kind, data, *self.destination, f'kind {kind}')
            message_type, seq, payload, peer = self.request()
            self.assertEqual(message_type, BULK_BEGIN)
            self.assertEqual(payload, struct.pack('<B3xI', kind, len(data)))
            # READY is a real barrier: no bytes leave before it arrives.
            self.board.settimeout(.03)
            with self.assertRaises(socket.timeout):
                self.board.recv(65535)
            self.board.settimeout(2)
            self.reply(peer, READY, seq, struct.pack('<B3x', kind))
            received = bytearray()
            while True:
                packet, source = self.board.recvfrom(65535)
                window, notify, offset, chunk = unpack(packet)
                self.assertEqual((window, offset, source), (0, len(received), peer))
                self.assertLessEqual(len(chunk), 1024)
                received.extend(chunk)
                if notify:
                    break
            self.assertEqual(received, data)
            self.assertTrue(self.eth.status()['tx']['active'])
            with self.assertRaises(RuntimeError):
                self.eth.showcase.bulk(3, b'next', *self.destination, 'next')
            self.reply(peer, DONE, seq, struct.pack('<BB2xI', kind, 0, index))
            wait_for(self, lambda: not self.eth.status()['tx']['active'])
            tx = self.eth.status()['tx']
            self.assertEqual((tx['sent'], tx['total'], tx['index']), (len(data), len(data), index))
            self.assertIsNone(tx['error'])

    def test_bulk_rejection_timeout_and_bad_reply_report_errors(self):
        for status, text in ((1, '长度不符'), (2, '格式错误'), (3, '空间不足')):
            self.eth.showcase.bulk(3, b'game', *self.destination, 'game')
            _, seq, _, peer = self.request()
            self.reply(peer, DONE, seq, struct.pack('<BB2xI', 3, status, 0))
            wait_for(self, lambda: not self.eth.status()['tx']['active'])
            self.assertIn(text, self.eth.status()['tx']['error'])
            self.assertEqual(self.eth.status()['tx']['sent'], 0)
        with patch('tools.debug_tool.core.showcase.RESPONSE_TIMEOUT', .05):
            self.eth.showcase.bulk(3, b'game', *self.destination, 'game')
            self.request()
            wait_for(self, lambda: not self.eth.status()['tx']['active'])
            self.assertIn('超时', self.eth.status()['tx']['error'])
        self.eth.showcase.bulk(3, b'game', *self.destination, 'game')
        _, seq, _, peer = self.request()
        self.reply(peer, READY, seq + 1, struct.pack('<B3x', 3))
        wait_for(self, lambda: not self.eth.status()['tx']['active'])
        self.assertIn('sequence', self.eth.status()['tx']['error'])

    def test_camera_and_echo_round_trip_and_loss(self):
        self.eth.start_receive(0)
        self.eth.showcase.app(1, destination=self.board.getsockname())
        kind, seq, payload, peer = self.request()
        self.reply(peer, ACK, seq, struct.pack('<HBB', APP, 2, 0))
        self.assertEqual((kind, payload), (APP, struct.pack('<BBH', 1, 0, 0)))
        wait_for(self, lambda: not self.eth.status()['tx']['active'])
        with patch('tools.debug_tool.core.showcase.RESPONSE_TIMEOUT', .08):
            self.eth.showcase.echo_test(3, *self.destination)
            for trial in range(3):
                kind, seq, payload, peer = self.request()
                self.assertEqual((kind, payload), (ECHO, struct.pack('<I', trial)))
                if trial != 1:
                    time.sleep(.005)
                    self.reply(peer, ECHO_REPLY, seq, payload)
            wait_for(self, lambda: not self.eth.status()['tx']['active'])
        echo = self.eth.status()['echo']
        self.assertEqual((echo['count'], echo['received'], echo['lost']), (3, 2, 1))
        self.assertGreaterEqual(echo['averageMs'], 5)
        self.assertIn('超时', self.eth.status()['tx']['error'])

    def test_edsc_receives_through_console_process_with_telemetry_alive(self):
        from tools.debug_tool.core.engine import SerialEngine
        engine = SerialEngine()
        engine.ethernet.local_ip = '127.0.0.1'
        self.addCleanup(engine.ethernet.stop_receive)
        self.addCleanup(engine.virtual_input.close)
        with TemporaryDirectory() as directory:
            engine.ethernet.start_receive(0, directory, mode='console')
            engine.ethernet.showcase.echo_test(1, *self.destination)
            kind, seq, payload, peer = self.request()
            self.reply(peer, ECHO_REPLY, seq, payload)
            wait_for(self, lambda: not engine.ethernet.status()['tx']['active'])
            self.assertEqual(engine.ethernet.status()['echo']['received'], 1)
            self.assertIsNone(engine.ethernet.status()['rx']['error'])

    def test_wheel_wrap_and_middle_button_both_transports(self):
        frames = []
        controller = VirtualInput(frames.append)
        self.addCleanup(controller.close)
        controller.update(0, 1, 2, 0, 255)
        controller.update(0, 1, 2, 0, 256)
        controller.update(0, 1, 2, 0, -1)
        controller.update(0, 1, 2, 4)
        self.assertEqual([FRAME.unpack(frame)[4] for frame in frames[:3]], [255, 0, 255])
        self.assertEqual(FRAME.unpack(frames[-1]), (0, 1, 2, 4, 255))
        from tools.debug_tool.core.engine import SerialEngine
        engine = SerialEngine()
        self.addCleanup(engine.virtual_input.close)
        with patch.object(engine, 'send') as send:
            with self.assertRaisesRegex(RuntimeError, '网口未连接'):
                send_frame(engine, frames[-1])
            send.assert_not_called()
        self.eth.start_receive(0)
        engine.ethernet = self.eth
        engine.board.steps['peer']['done'] = True
        engine.board.network_endpoint = self.board.getsockname()
        send_frame(engine, frames[-1])
        packet = self.board.recv(65535)
        self.assertEqual(unpack(packet), (2, True, 0, frames[-1]))


class GameRecordTest(unittest.TestCase):
    def test_every_edg2_and_edgp_field(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtGui import QImage
        from PySide6.QtWidgets import QApplication
        app = QApplication.instance() or QApplication([])
        with TemporaryDirectory() as directory:
            records = []
            for extension in ('png', 'jpg'):
                path = Path(directory) / f'cover.{extension}'
                image = QImage(240, 160, QImage.Format_RGB888)
                image.fill('red')
                self.assertTrue(image.save(str(path)))
                rom = b'NES\x1a' + bytes(range(255))
                record = build_record('超级马里奥超级马里奥超级马里奥', rom, path)
                fields = struct.unpack_from('<4sHHIHHIHHIII64s', record)
                magic, version, reserved, total, nw, nh, no, cw, ch, co, ro, rl, name = fields
                self.assertEqual((magic, version, reserved, total), (b'EDG2', 2, 0, len(record)))
                self.assertEqual((cw, ch, rl), (120, 160, len(rom)))
                self.assertEqual(name.rstrip(b'\0').decode(), '超级马里奥超级马里奥超级马里奥')
                self.assertEqual(no, 100)
                self.assertTrue(0 < nw <= 180)
                self.assertGreater(nh, 20)  # All characters wrap at the specified 20 px.
                self.assertTrue(any(record[no:no + nw * nh]))
                self.assertEqual((no % 4, co % 4, ro % 4), (0, 0, 0))
                self.assertEqual(co, (no + nw * nh + 3) & ~3)
                self.assertEqual(ro, co + cw * ch * 2)
                self.assertEqual(record[ro:ro + rl], rom)
                self.assertEqual(record[ro + rl:], bytes(-rl % 4))
                # The 3:2 cover occupies 120x80, centered without cropping in white.
                self.assertEqual(record[co:co + 2], b'\xff\xff')
                center = co + (80 * 120 + 60) * 2
                value = struct.unpack_from('<H', record, center)[0]
                self.assertGreaterEqual(value >> 11, 30)
                self.assertLessEqual((value >> 5) & 63, 1)
                records.append(record)
            bare = build_record('无封面', b'rom', None)
            fields = struct.unpack_from('<4sHHIHHIHHIII64s', bare)
            self.assertEqual(fields[7:10], (0, 0, 0))
            self.assertEqual(bare[fields[10]:fields[10] + fields[11]], b'rom')
            records.append(bare)
            pack = build_pack(records)
            self.assertEqual(struct.unpack_from('<4sHH', pack), (b'EDGP', 2, 3))
            offsets = struct.unpack_from('<3I', pack, 8)
            self.assertEqual(offsets[0], 20)
            for offset, record in zip(offsets, records):
                self.assertEqual(offset % 4, 0)
                self.assertEqual(pack[offset:offset + len(record)], record)
            self.assertEqual(offsets[1], offsets[0] + len(records[0]))
        app.processEvents()


class ShowcaseGuiTest(unittest.TestCase):
    def test_game_selection_upload_progress_errors_and_layout(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        sys.path.insert(0, str(ROOT / 'tools/debug_tool'))
        from PySide6.QtCore import QCoreApplication, QEvent, QPoint, QPointF, Qt
        from PySide6.QtGui import QWheelEvent
        from PySide6.QtTest import QTest
        from PySide6.QtWidgets import QApplication, QLabel, QPushButton
        from core.engine import SerialEngine
        from gui.app import MainWindow
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        frames = []
        engine.virtual_input.send = frames.append
        window = MainWindow(engine)
        window.setAttribute(Qt.WA_DeleteOnClose)
        try:
            window.show()
            window._select_page(6)
            panel = window.games
            with TemporaryDirectory() as directory:
                rom = Path(directory) / '超级马里奥.nes'
                rom.write_bytes(b'NES\x1a\0\0')
                with patch('gui.games.QFileDialog.getOpenFileName', return_value=(str(rom), '')):
                    panel.choose_rom()
                self.assertEqual(panel.name.text(), rom.stem)
                with (patch.object(engine.ethernet.showcase, 'bulk') as bulk,
                      patch.object(engine.ethernet, 'listen_console')):
                    panel.upload.click()
                    kind, record, ip, port, local_port, name = bulk.call_args.args
                    self.assertEqual((kind, port, local_port), (3, 5000, 6000))
                    fields = struct.unpack_from('<4sHHIHHIHHIII64s', record)
                    self.assertEqual(record[fields[10]:fields[10] + fields[11]], rom.read_bytes())
                engine.ethernet.tx = dict(active=True, sent=50, total=100, packets=1,
                                           path='游戏 · 超级马里奥', error=None, phase='上传中', index=None)
                panel.refresh()
                self.assertEqual(panel.progress.value(), 50)
                self.assertFalse(panel.upload.isEnabled())
                engine.ethernet.tx.update(active=False, sent=100, index=31)
                panel.refresh()
                self.assertIn('板端序号 31', panel.result.text())
                self.assertTrue(panel.upload.isEnabled())
                engine.ethernet.tx.update(error='空间不足')
                panel.refresh()
                self.assertIn('空间不足', panel.result.text())
                panel.rom.setText(str(rom.parent / 'missing.nes'))
                panel.upload.click()
                panel.refresh()
                self.assertIn('missing.nes', panel.result.text())
                self.assertIn('missing.nes', engine.board.error)
            for width, height in ((1366, 768), (1920, 1080)):
                window.resize(width, height)
                app.processEvents()
                self.assertEqual((window.width(), window.height()), (width, height))
                for label in panel.findChildren(QLabel):
                    if not label.wordWrap():
                        self.assertGreaterEqual(label.width(),
                                                label.fontMetrics().horizontalAdvance(label.text()))
                for button in panel.findChildren(QPushButton):
                    text_width = button.fontMetrics().horizontalAdvance(button.text())
                    self.assertGreaterEqual(button.width(), text_width + 20)
                window.rail_group.button(6).setChecked(True)
                window.grab().save(str(ROOT / f'build/games-{width}x{height}.png'))
            engine.board.mark('peer')
            engine.ethernet.rx_socket = Mock()
            window._select_page(5)
            input_panel = window.virtual_input
            # Qt's global button state can outlive widgets used by prior layout tests.
            QTest.mouseRelease(input_panel.pad, Qt.LeftButton)
            QTest.mouseRelease(input_panel.pad, Qt.RightButton)
            QTest.mouseRelease(input_panel.pad, Qt.MiddleButton)
            QTest.mousePress(input_panel.pad, Qt.MiddleButton)
            self.assertEqual(FRAME.unpack(frames[-1])[3], 4)
            QTest.mouseRelease(input_panel.pad, Qt.MiddleButton)
            for delta, expected in ((120, 255), (-120, 0)):
                event = QWheelEvent(QPointF(100, 100), QPointF(100, 100), QPoint(),
                                    QPoint(0, delta), Qt.NoButton, Qt.NoModifier,
                                    Qt.NoScrollPhase, False)
                app.sendEvent(input_panel.pad, event)
                self.assertEqual(FRAME.unpack(frames[-1])[4], expected)
            QTest.keyPress(input_panel, Qt.Key_J)
            window._select_page(0)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            engine.virtual_input.update(1, 0, 0, 0, 1)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 1)
        finally:
            engine.ethernet.tx['active'] = False
            engine.ethernet.rx_socket = None
            window.close()
            QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
            app.processEvents()
