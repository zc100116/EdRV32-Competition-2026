"""test_b3n.py — T-NETN, SoC 7.2/7.4; actual CH2/OUTPUT/EDDT UDP; host clock.

Exercise arbitrary input dimensions, input_pack, NPU/Python post references,
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
from tools.debug_tool.core.yolo import INPUT_BYTES, OUTPUT_BYTES, reference_b3n_input

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/debug_tool'))
from telemetry_sim import run_b3n


class B3NTest(unittest.TestCase):
    def test_ch2_udp_reference_and_alternating_windows(self):
        import cv2
        import numpy as np
        engine = SerialEngine()
        self.addCleanup(engine.ethernet.stop_receive)
        engine.board.select_project('B3N')
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
                        run_b3n(board, directory, quant, 2)
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
                                                   port, window)
                        deadline = time.monotonic() + 20
                        while engine.yolo.snapshot()[0] != window + 1:
                            self.assertLess(time.monotonic(), deadline, errors)
                            time.sleep(.01)
                        _, capture = engine.yolo.snapshot()
                        self.assertEqual(capture[0], reference_b3n_input(path))
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
        engine.board.select_project('B3N')
        engine.yolo.reset_capture()
        with self.assertRaisesRegex(ValueError, 'WIN 1: incomplete'):
            engine.yolo.receive(2, 0, struct.pack('<4sHHII', b'EDDT', 1, 0, 0, 0), True)

    def test_folder_order_completion_stats_and_original_image(self):
        from PySide6.QtGui import QImage
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        console = SocConsole(engine, lambda text: None)
        self.addCleanup(console.close)
        console.project.setCurrentText('B3N')
        self.assertTrue(console.choose_folder.isEnabled())
        self.assertTrue(console.view.isEnabled())
        self.assertFalse(console.apply_scene.isEnabled())
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
                self.assertEqual(console.window.currentIndex(), 1)
                def result():
                    return dict(input=dict(count=0, first=None),
                                output=dict(count=0, first=None),
                                detections=dict(count=0, expected=0, actual=0))
                console.comparison = result()
                console.refresh()
                self.assertEqual(sent, [str(directory / 'a.png'), str(directory / 'b.png')])
                self.assertEqual(console.window.currentIndex(), 0)
                console.comparison = result()
                console.refresh()
                self.assertEqual(console.folder_completed, 2)
                self.assertIsNone(console.folder_started)
        app.processEvents()
