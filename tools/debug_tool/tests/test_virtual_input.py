"""Task T-VIN1: complete wire states, UDP loopback, UART emit and Qt controls."""
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

from tools.debug_tool.core.virtual_input import FRAME, VirtualInput

ROOT = Path(__file__).resolve().parents[3]


class VirtualInputTest(unittest.TestCase):
    def test_uart_emit_repeat(self):
        output = ROOT / 'build/debug_tool/virtual-input.bin'
        output.parent.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        subprocess.run([sys.executable, 'tools/debug_tool/virtual_input.py', '--emit',
                        str(output), '--keys', 'up,a,next', '--x', '1279', '--y', '719',
                        '--mouse', '3', '--hold', '.22'], cwd=ROOT, check=True)
        raw = output.read_bytes()
        self.assertEqual(len(raw) % 10, 0)
        frames = [raw[i:i + 10] for i in range(0, len(raw), 10)]
        self.assertTrue(10 <= len(frames) <= 15, len(frames))
        held = b'\x1bV' + FRAME.pack(0x411, 1279, 719, 3, 0)
        self.assertTrue(all(frame == held for frame in frames[:-1]))
        self.assertEqual(frames[-1], b'\x1bV' + FRAME.pack(0, 1279, 719, 0, 0))
        self.assertGreaterEqual(time.monotonic() - started, .22)

    def test_udp_loopback_repeat(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1', 0))
            sock.settimeout(.5)
            process = subprocess.Popen([
                sys.executable, 'tools/debug_tool/virtual_input.py', '--udp',
                f'127.0.0.1:{sock.getsockname()[1]}', '--keys', 'b,start',
                '--x', '300', '--y', '200', '--hold', '.22'], cwd=ROOT)
            packets = []
            times = []
            while True:
                packet = sock.recv(1024)
                packets.append(packet)
                times.append(time.monotonic())
                if packet[8:10] == b'\0\0':
                    break
            self.assertEqual(process.wait(timeout=2), 0)
            self.assertTrue(10 <= len(packets) <= 15, len(packets))
            self.assertTrue(all(packet[:8] == struct.pack('!BBHI', 2, 1, 0, 0)
                                for packet in packets))
            self.assertTrue(all(packet[8:] == FRAME.pack(0xa0, 300, 200, 0, 0)
                                for packet in packets[:-1]))
            average = (times[-2] - times[0]) / (len(times) - 2)
            self.assertTrue(.015 <= average <= .03, average)

    def test_connected_network_else_serial(self):
        from tools.debug_tool.core.engine import SerialEngine
        from tools.debug_tool.core.virtual_input import channel, send_frame
        engine = SerialEngine()
        engine.ethernet.local_ip = "127.0.0.1"
        serial = []
        engine.send = lambda text, ending, hex_mode: serial.append(bytes.fromhex(text))
        frame = FRAME.pack(0, 1, 2, 0, 0)
        send_frame(engine, frame)
        self.assertEqual(serial, [b'\x1bV' + frame])
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
            receiver.bind(('127.0.0.1', 0))
            receiver.settimeout(1)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
                engine.ethernet.rx_socket = sender
                engine.ethernet.rx['active'] = True
                engine.board.steps['peer']['done'] = True
                engine.board.network_endpoint = receiver.getsockname()
                self.assertEqual(channel(engine), '网口')
                send_frame(engine, frame)
                self.assertEqual(receiver.recv(1024), struct.pack('!BBHI', 2, 1, 0, 0) + frame)
                self.assertEqual(len(serial), 1)
            engine.ethernet.rx_socket = None
        engine.virtual_input.close()

    def test_changes_and_idle(self):
        frames = []
        controller = VirtualInput(frames.append)
        try:
            controller.update(0, 500, 300, 0)
            controller.update(0, 500, 300, 0)
            time.sleep(.07)
            self.assertEqual(frames, [FRAME.pack(0, 500, 300, 0, 0)])
        finally:
            controller.close()

    def test_gui_focus_keyboard_pointer_and_layout(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        sys.path.insert(0, str(ROOT / 'tools/debug_tool'))
        from PySide6.QtCore import QPoint, Qt
        from PySide6.QtTest import QTest
        from PySide6.QtWidgets import QApplication, QLabel
        from core.engine import SerialEngine
        from gui.app import MainWindow
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        engine.ethernet.local_ip = "127.0.0.1"
        frames = []
        engine.virtual_input.close()
        engine.virtual_input = VirtualInput(frames.append)
        window = MainWindow(engine)
        window.setAttribute(Qt.WA_DeleteOnClose)
        try:
            window.show()
            window.soc.toggle_panel(window.soc.monitor_card)
            window._select_page(5)
            panel = window.virtual_input
            # A focus elsewhere in the window must not require a panel click.
            window.rail_group.button(5).setFocus()
            app.processEvents()
            QTest.keyPress(window, Qt.Key_W)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 1)
            self.assertTrue(panel.buttons['up'].isDown())
            QTest.keyPress(window, Qt.Key_Up)
            QTest.keyRelease(window, Qt.Key_W)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 1)
            self.assertTrue(panel.buttons['up'].isDown())
            QTest.keyRelease(window, Qt.Key_Up)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            self.assertFalse(panel.buttons['up'].isDown())
            for field in (panel.ip, panel.local_ip):
                field.setFocus()
                with patch.object(engine.virtual_input, 'update') as update:
                    QTest.keyClick(field, Qt.Key_W)
                    update.assert_not_called()
                self.assertIn('w', field.text().lower())
            panel.ip.setText('192.168.1.10')
            panel.local_ip.setText('127.0.0.1')
            QTest.mousePress(panel.buttons['a'], Qt.LeftButton)
            self.assertTrue(panel.buttons['a'].isDown())
            self.assertEqual(FRAME.unpack(frames[-1])[0], 16)
            QTest.mouseRelease(panel.buttons['a'], Qt.LeftButton)
            self.assertFalse(panel.buttons['a'].isDown())
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            QTest.keyPress(panel, Qt.Key_Tab, Qt.ShiftModifier)
            self.assertTrue(panel.buttons['prev'].isDown())
            self.assertEqual(FRAME.unpack(frames[-1])[0], 1 << 11)
            QTest.keyRelease(panel, Qt.Key_Tab, Qt.ShiftModifier)
            self.assertFalse(panel.buttons['prev'].isDown())
            for width, height in ((1366, 768), (1920, 1080)):
                window.resize(width, height)
                app.processEvents()
                self.assertEqual((window.width(), window.height()), (width, height))
                for label in panel.findChildren(QLabel):
                    if not label.wordWrap():
                        self.assertGreaterEqual(label.width(),
                                                label.fontMetrics().horizontalAdvance(label.text()))
                for button in panel.buttons.values():
                    self.assertGreaterEqual(button.width(),
                                            button.fontMetrics().horizontalAdvance(button.text())
                                            + 24)
                area = panel.pad.area()
                self.assertAlmostEqual(area.width() / area.height(), 16 / 9)
            with patch.object(engine.board, 'establish_network') as establish:
                panel.connect_button.click()
                establish.assert_called_once_with('192.168.1.10', 5000, '127.0.0.1')
            with patch.object(engine, 'send') as send:
                window.soc.status_query.click()
                send.assert_called_once_with('status', 'cr')
            panel.setFocus()
            QTest.keyPress(panel, Qt.Key_J)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 16)
            QTest.keyRelease(panel, Qt.Key_J)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            QTest.keyPress(panel, Qt.Key_Escape)
            self.assertTrue(panel.buttons['esc'].isDown())
            self.assertIs(window.soc.expanded_panel, window.soc.monitor_card)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 1 << 9)
            QTest.keyRelease(panel, Qt.Key_Escape)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            QTest.keyPress(panel, Qt.Key_Tab)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 1 << 10)
            QTest.keyRelease(panel, Qt.Key_Tab)
            area = panel.pad.area()
            QTest.mousePress(panel.pad, Qt.LeftButton, pos=QPoint(int(area.right()),
                                                                  int(area.bottom())))
            _, x, y, mouse, _ = FRAME.unpack(frames[-1])
            self.assertEqual((x, y, mouse), (1279, 719, 1))
            QTest.mouseRelease(panel.pad, Qt.LeftButton)
            self.assertEqual(FRAME.unpack(frames[-1])[3], 0)
            QTest.keyPress(panel, Qt.Key_W)
            from PySide6.QtCore import QEvent
            app.sendEvent(window, QEvent(QEvent.WindowDeactivate))
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            self.assertFalse(panel.buttons['up'].isDown())
            QTest.keyPress(panel, Qt.Key_W)
            window._select_page(4)
            self.assertEqual(FRAME.unpack(frames[-1])[0], 0)
            self.assertFalse(panel.buttons['up'].isDown())
            with patch.object(engine.virtual_input, 'update') as update:
                QTest.keyClick(window, Qt.Key_W)
                update.assert_not_called()
        finally:
            from PySide6.QtCore import QCoreApplication, QEvent
            window.close()
            QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
            app.processEvents()


if __name__ == '__main__':
    unittest.main()
