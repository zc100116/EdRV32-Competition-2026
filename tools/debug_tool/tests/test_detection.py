"""test_b3n.py — T-NETN, SoC 7.2/7.4; actual CH2/OUTPUT/EDDT UDP; host clock.

Exercise arbitrary input dimensions, VIN adaptation, NPU/Python post references,
alternating windows and the shared console receiver without RTL or board access.
"""
import json
from pathlib import Path
import socket
import struct
import sys
from tempfile import TemporaryDirectory
import threading
import time
import unittest
from unittest.mock import patch

from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.yolo import INPUT_BYTES, OUTPUT_BYTES, reference_input

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/debug_tool'))
from telemetry_sim import run_detection


class ImageDetectionTest(unittest.TestCase):
    def setUp(self):
        ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                      return_value=('loopback', 0.0))
        ready.start()
        self.addCleanup(ready.stop)

    def test_ch2_udp_reference_and_alternating_windows(self):
        import cv2
        import numpy as np
        engine = SerialEngine()
        engine.ethernet.local_ip = "127.0.0.1"
        self.addCleanup(engine.ethernet.stop_receive)
        quant = json.loads((ROOT / 'tasks/win/20261029-09-b3-software/src/npu/'
                            'quantization.json').read_text())
        with TemporaryDirectory(dir=ROOT / 'build') as directory:
            directory = Path(directory)
            # Legal nearest-neighbor descriptor; input bytes affect the first output cells.
            words = [0] * 16
            words[0] = 2 | (2 << 12) | (3 << 14)
            words[1] = 12 * 640 * 4  # Skip the CH2 letterbox's top padding.
            words[3] = 245760  # D0 class logits: preserve a nonempty detection return.
            words[2], words[4] = 32, 64
            words[8], words[9], words[10] = 0x10001, 0x20002, 1
            desc = struct.pack('<16I', *words)
            (directory / 'regs.txt').write_text(
                'DESC_BASE 00080000\nDESC_COUNT 1\nMODEL_BASE 00100000\n'
                'WORK_BASE 01000000\nINPUT_BASE 04000000\nOUTPUT_BASE 05000000\n')
            (directory / 'mem_desc.hex').write_text(
                '@00004000\n' + '\n'.join(desc[i:i + 32][::-1].hex()
                                         for i in range(0, 64, 32)))
            paths = []
            for index, shape in enumerate(((31, 57), (55, 23))):
                image = np.zeros((*shape, 3), dtype=np.uint8)
                image[:, :, index] = 255
                path = directory / f'{index}.png'
                self.assertTrue(cv2.imwrite(str(path), image))
                paths.append(path)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as board:
                board.bind(('127.0.0.1', 0))
                board.settimeout(20)
                engine.ethernet.start_receive(0, directory / 'rx', mode='console')
                port = engine.ethernet.status()['rx']['localPort']
                errors = []
                def simulate():
                    try:
                        run_detection(board, directory, quant, 2)
                    except Exception as exc:
                        errors.append(exc)
                worker = threading.Thread(target=simulate)
                worker.start()
                try:
                    for window, path in enumerate(paths):
                        send_blocks = engine.ethernet.send_blocks
                        # Model a paced wire; localhost socket buffers are smaller than CH2.
                        def paced(blocks, *args, **kwargs):
                            return send_blocks(blocks, *args, interval=.0002, **kwargs)
                        with patch.object(engine.ethernet, 'send_blocks', side_effect=paced):
                            engine.yolo.send_image(path, '127.0.0.1', board.getsockname()[1],
                                                   port)
                        deadline = time.monotonic() + 20
                        while engine.yolo.snapshot()[0] != window + 1:
                            self.assertLess(time.monotonic(), deadline, errors)
                            time.sleep(.01)
                        _, capture = engine.yolo.snapshot()
                        self.assertEqual(capture[0], reference_input(path))
                        self.assertEqual(len(capture[0]), INPUT_BYTES)
                        self.assertEqual(len(capture[1]), OUTPUT_BYTES)
                        self.assertEqual(capture[2].frame_id, window)
                        self.assertGreater(len(capture[2].boxes), 0)
                        result = engine.yolo.compare(path, directory, quant)
                        self.assertEqual(result['input']['count'], 0)
                        self.assertEqual(result['output']['count'], 0)
                        self.assertEqual(result['detections']['count'], 0)
                        self.assertGreater(engine.yolo.timings[-1]['seconds'], 0)
                finally:
                    worker.join(21)
                self.assertFalse(worker.is_alive())
                self.assertEqual(errors, [])
                self.assertEqual(len(engine.yolo.timings), 2)
                self.assertIsNone(engine.ethernet.status()['rx']['error'])

    def test_b3n_incomplete_output_is_reported(self):
        engine = SerialEngine()
        engine.yolo.reset_capture()
        engine.yolo.receive(2, 0, struct.pack('<4sHHII', b'EDDT', 1, 0, 0, 0), True)
        self.assertIn('window 0: missing 983040 B', engine.yolo.error)
        self.assertEqual(engine.yolo.failed, 1)

    def test_missing_return_then_complete_preserves_receiver_and_telemetry(self):
        from tools.debug_tool.core.ethernet import packets
        from test_program import wait_for
        from test_telemetry import wire
        engine = SerialEngine()
        engine.ethernet.local_ip = '127.0.0.1'
        self.addCleanup(engine.ethernet.stop_receive)
        with TemporaryDirectory() as directory:
            state = engine.ethernet.start_receive(0, directory, mode='console')
            destination = '127.0.0.1', state['localPort']
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as source:
                def send_return(missing, end=True):
                    engine.yolo.reset_capture()
                    for window, size in enumerate((INPUT_BYTES, OUTPUT_BYTES)):
                        for index, packet in enumerate(packets(bytes(size), window, 0)):
                            if missing and index == 5:
                                continue
                            source.sendto(packet[:1] + b'\0' + packet[2:], destination)
                            time.sleep(.0002)
                    detections = struct.pack('<4sHHII', b'EDDT', 1, 0, 7, 0)
                    if end:
                        source.sendto(next(packets(detections, 2, 0)), destination)

                send_return(True)
                wait_for(self, lambda: engine.yolo.failed == 1)
                self.assertIn('window 0: missing 1024 B', engine.yolo.error)
                self.assertIn('window 1: missing 1024 B', engine.yolo.error)
                self.assertTrue(engine.ethernet.status()['rx']['active'])
                self.assertTrue(engine.ethernet.rx_process.is_alive())
                source.sendto(next(packets(wire(1), 3, 0)), destination)
                wait_for(self, lambda: engine.telemetry.status()['records'] == 1)
                send_return(False)
                wait_for(self, lambda: engine.yolo.snapshot()[1] is not None)
                self.assertEqual(engine.yolo.failed, 1)
                self.assertIsNone(engine.yolo.error)
                self.assertEqual(engine.yolo.snapshot()[1][2].frame_id, 7)
                self.assertTrue(engine.ethernet.status()['rx']['active'])
                send_return(False, end=False)
                # Other windows must not postpone the missing-EDDT deadline.
                for seq in range(2, 25):
                    source.sendto(next(packets(wire(seq), 3, 0)), destination)
                    time.sleep(.05)
                wait_for(self, lambda: engine.yolo.failed == 2)
                self.assertEqual(engine.yolo.error, '回传未结束（超时 1 s）')
                send_return(False)
                wait_for(self, lambda: engine.yolo.snapshot()[1] is not None)
                self.assertEqual(engine.yolo.failed, 2)
                self.assertTrue(engine.ethernet.status()['rx']['active'])
            engine.ethernet.stop_receive()
            self.assertIsNone(engine.ethernet.status()['rx']['error'])
            self.assertIsNone(engine.ethernet.rx_memory)
            self.assertIsNone(engine.ethernet.rx_process)

    def test_folder_continues_after_failed_return(self):
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        console = SocConsole(engine, lambda text: None)
        self.addCleanup(console.close)
        console.folder_images = [Path('next.png')]
        console.folder_started = time.monotonic()
        engine.yolo.reset_capture()
        engine.yolo.receive(2, 0, struct.pack('<4sHHII', b'EDDT', 1, 0, 0, 0), True)
        with patch.object(console, '_send_image') as send:
            console.refresh()
            send.assert_called_once()
            self.assertEqual(console.image_path.text(), 'next.png')
            self.assertEqual(engine.yolo.failed, 1)
            self.assertIn('失败 1 张', console.capture_status.text())
            console.refresh()
            send.assert_called_once()
        app.processEvents()

    def test_malformed_return_is_still_a_fatal_protocol_error(self):
        from tools.debug_tool.core.ethernet import packets
        from test_program import wait_for
        engine = SerialEngine()
        engine.ethernet.local_ip = '127.0.0.1'
        self.addCleanup(engine.ethernet.stop_receive)
        with TemporaryDirectory() as directory:
            state = engine.ethernet.start_receive(0, directory, mode='yolo')
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as source:
                data = struct.pack('<4sHHII', b'EDDT', 2, 0, 0, 0)
                source.sendto(next(packets(data, 2, 0)), ('127.0.0.1', state['localPort']))
            wait_for(self, lambda: not engine.ethernet.status()['rx']['active'])
            self.assertIn('magic/version', engine.ethernet.status()['rx']['error'])
            self.assertEqual(engine.yolo.failed, 0)
            engine.ethernet.stop_receive()
            self.assertIsNone(engine.ethernet.rx_memory)

    def test_return_timeout_uses_last_packet_or_send_completion(self):
        from tools.debug_tool.core.yolo import YoloTool
        yolo = YoloTool(None)
        with patch('tools.debug_tool.core.yolo.time.monotonic', return_value=10):
            yolo.reset_capture()
            yolo.image_sent(None)
        with patch('tools.debug_tool.core.yolo.time.monotonic', return_value=10.9):
            yolo.check_timeout()
            self.assertEqual(yolo.failed, 0)
            yolo.receive(0, 0, bytes(1024), False)
        with patch('tools.debug_tool.core.yolo.time.monotonic', return_value=11.5):
            yolo.check_timeout()
            self.assertEqual(yolo.failed, 0)
        with patch('tools.debug_tool.core.yolo.time.monotonic', return_value=11.9):
            yolo.check_timeout()
            self.assertEqual(yolo.failed, 1)
            self.assertEqual(yolo.error, '回传未结束（超时 1 s）')
            yolo.check_timeout()
            self.assertEqual(yolo.failed, 1)
            yolo.reset_capture()
            yolo.check_timeout()
            self.assertEqual(yolo.failed, 1)  # Upload has not finished yet.
            yolo.image_sent(None)
        with patch('tools.debug_tool.core.yolo.time.monotonic', return_value=12.9):
            yolo.check_timeout()
            self.assertEqual(yolo.failed, 2)

    def test_folder_order_completion_stats_and_original_image(self):
        from PySide6.QtGui import QImage
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        console = SocConsole(engine, lambda text: None)
        self.addCleanup(console.close)
        self.assertTrue(console.choose_folder.isEnabled())
        self.assertTrue(console.view.isEnabled())
        self.assertTrue(console.apply_scene.isEnabled())
        with TemporaryDirectory(dir=ROOT / 'build') as directory:
            directory = Path(directory)
            image = QImage(33, 17, QImage.Format_RGB888)
            image.fill('green')
            for name in ('b.png', 'a.png'):
                self.assertTrue(image.save(str(directory / name)))
            console.image_path.setText(str(directory / 'b.png'))
            console._load_image()
            self.assertEqual((console.static_image.width(), console.static_image.height()),
                             (33, 17))
            sent = []
            with (patch('gui.soc_console.QFileDialog.getExistingDirectory',
                        return_value=str(directory)),
                  patch.object(console, '_send_image',
                               side_effect=lambda: sent.append(console.image_path.text()))):
                console._choose_folder()
                self.assertEqual(sent, [str(directory / 'a.png')])
                self.assertEqual(engine.yolo.next_window, 0)
                # Each complete capture advances the folder independently of reference setup.
                from tools.debug_tool.core.video import parse_detections
                from unittest.mock import patch as mock_patch
                capture = (bytes(INPUT_BYTES), bytes(OUTPUT_BYTES),
                           parse_detections(struct.pack('<4sHHII', b'EDDT', 1, 0, 0, 0)))
                with mock_patch.object(engine.yolo, 'snapshot', return_value=(1, capture)):
                    console.refresh()
                self.assertEqual(sent, [str(directory / 'a.png'), str(directory / 'b.png')])
                with mock_patch.object(engine.yolo, 'snapshot', return_value=(2, capture)):
                    console.refresh()
                self.assertEqual(console.folder_completed, 2)
                self.assertIsNone(console.folder_started)
        app.processEvents()
