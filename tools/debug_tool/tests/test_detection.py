"""test_b3n.py — T-NETN, SoC 7.2/7.4; actual CH2/OUTPUT/EDDT UDP; host clock.

Exercise arbitrary input dimensions, VIN adaptation, NPU/Python post references,
showcase bulk transfers and the shared console receiver without RTL or board access.
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
from tools.debug_tool.core.yolo import INPUT_BYTES, OUTPUT_BYTES, reference_input, parse_candidates

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/debug_tool'))
from telemetry_sim import run_detection


class ImageDetectionTest(unittest.TestCase):
    def setUp(self):
        ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                      return_value=('loopback', 0.0))
        ready.start()
        self.addCleanup(ready.stop)

    def test_ch2_udp_reference_and_showcase_bulk(self):
        import cv2
        import numpy as np
        engine = SerialEngine()
        engine.ethernet.local_ip = "127.0.0.1"
        self.addCleanup(engine.ethernet.stop_receive)
        from tools.debug_tool.core.ethernet import packets as wire_packets
        def paced_packets(data, window, offset):
            for packet in wire_packets(data, window, offset):
                if window == 0 and len(data) > 1024:
                    time.sleep(.0002)  # Model the wire, as in the original upload test.
                yield packet
        pacing = patch('tools.debug_tool.core.ethernet.packets', paced_packets)
        pacing.start()
        self.addCleanup(pacing.stop)
        quant = json.loads((ROOT / 'tasks/win/20261029-09-b3-software/src/npu/'
                            'quantization.json').read_text())
        with TemporaryDirectory(dir=ROOT / 'build') as directory:
            directory = Path(directory)
            # Legal nearest-neighbor descriptor; input bytes affect the first output cells.
            words = [0] * 16
            words[0] = 2 | (2 << 12) | (3 << 14)
            words[1] = (12 + 180) * 640 * 4 + 320 * 4  # Center stays inside either letterbox.
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
                        engine.yolo.send_image(path, '127.0.0.1', board.getsockname()[1], port)
                        deadline = time.monotonic() + 20
                        while (engine.yolo.snapshot()[0] != window + 1 or
                               engine.ethernet.status()['tx']['active']):
                            self.assertLess(time.monotonic(), deadline, errors)
                            time.sleep(.01)
                        _, capture = engine.yolo.snapshot()
                        self.assertIsNotNone(capture, (engine.yolo.error, engine.ethernet.status(), errors))
                        self.assertEqual(capture[0], reference_input(path))
                        self.assertEqual(len(capture[0]), INPUT_BYTES)
                        self.assertEqual(len(capture[1]),
                                         4 + 24 * len(parse_candidates(capture[1])))
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
        engine.yolo.request = 0
        engine.yolo.reset_capture()
        engine.yolo.receive(2, 0, struct.pack('<4sHHII', b'EDDT', 1, 0, 0, 0), True)
        self.assertIsNone(engine.yolo.error)
        with self.assertRaisesRegex(ValueError, '回传不完整'):
            engine.yolo.complete_capture()
        self.assertIn('window 1 missing candidate count', engine.yolo.error)
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
                    engine.yolo.request = 0
                    engine.yolo.reset_capture()
                    for window, size in enumerate((INPUT_BYTES, 4)):
                        for index, packet in enumerate(packets(bytes(size), window, 0)):
                            if missing and index == 5:
                                continue
                            source.sendto(packet[:1] + b'\0' + packet[2:], destination)
                            time.sleep(.0002)
                    detections = struct.pack('<4sHHII', b'EDDT', 1, 0, 7, 0)
                    if end:
                        source.sendto(next(packets(detections, 2, 0)), destination)

                send_return(True)
                wait_for(self, lambda: engine.yolo.capture_error is not None)
                self.assertTrue(engine.yolo.capture_pending)
                with self.assertRaisesRegex(ValueError, '回传不完整'):
                    engine.yolo.complete_capture()
                self.assertIn('window 0: missing 1024 B', engine.yolo.error)
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
                # Telemetry does not finish an image; only BULK DONE does.
                for seq in range(2, 5):
                    source.sendto(next(packets(wire(seq), 3, 0)), destination)
                    time.sleep(.05)
                self.assertTrue(engine.yolo.capture_pending)
                with self.assertRaisesRegex(ValueError, '回传不完整'):
                    engine.yolo.complete_capture()
                self.assertEqual(engine.yolo.failed, 2)
                send_return(False)
                wait_for(self, lambda: engine.yolo.snapshot()[1] is not None)
                self.assertEqual(engine.yolo.failed, 2)
                self.assertTrue(engine.ethernet.status()['rx']['active'])
            engine.ethernet.stop_receive()
            self.assertIsNone(engine.ethernet.status()['rx']['error'])
            self.assertIsNone(engine.ethernet.rx_memory)
            self.assertIsNone(engine.ethernet.rx_process)

    def test_camera_buttons_send_edsc_command_and_select_video(self):
        from PySide6.QtWidgets import QApplication
        from gui.soc_console import SocConsole
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        console = SocConsole(engine, lambda text: None)
        self.addCleanup(console.close)
        with (patch.object(engine.ethernet, 'start_receive'),
              patch.object(engine.ethernet.showcase, 'app') as send,
              patch.object(engine.ethernet.showcase, 'command') as chain_send):
            for button in (console.image_camera, console.video_camera):
                engine.yolo.return_view = True
                button.click()
                self.assertEqual(send.call_args.args, (1,))
                self.assertEqual(send.call_args.kwargs['destination'], (console.ip.text(), 5000))
                self.assertEqual(console.display.currentIndex(), 0)
                self.assertEqual(console.scene.currentIndex(), 0)
                self.assertFalse(engine.yolo.return_view)
                from tools.debug_tool.core.pipeline import unpack_chain
                self.assertEqual(unpack_chain(chain_send.call_args.args[1])['source'], 0)
            self.assertEqual(send.call_count, 2)
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

    def test_return_stays_pending_until_done(self):
        from tools.debug_tool.core.yolo import YoloTool
        yolo = YoloTool(None)
        yolo.reset_capture()
        yolo.receive(0, 0, bytes(INPUT_BYTES), False)
        yolo.receive(1, 0, bytes(4), False)
        yolo.receive(2, 0, struct.pack('<4sHHII', b'EDDT', 1, 0, 9, 0), True)
        self.assertTrue(yolo.capture_pending)
        self.assertEqual(yolo.generation, 0)
        yolo.complete_capture()
        self.assertFalse(yolo.capture_pending)
        self.assertEqual(yolo.generation, 1)
