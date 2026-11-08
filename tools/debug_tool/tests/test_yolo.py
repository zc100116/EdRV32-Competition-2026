"""test_yolo.py — B2 design 3.5a and SoC 4.5 transfer vectors; host clock domain."""

import json
from pathlib import Path
import struct
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from tools.debug_tool.core.ethernet import EthernetTool
from tools.debug_tool.core.scene import SceneControl
from tools.debug_tool.core.yolo import (pack_model, rgb_to_rgb565, YoloTool,
    pack_candidates, parse_candidates, candidate_difference, INPUT_BYTES)


def compiler_fixture(directory):
    directory = Path(directory)
    (directory / 'regs.txt').write_text(
        'DESC_BASE 00080000\nMODEL_BASE 00100000\nDESC_COUNT 00000001\n'
        'WORK_BASE 01000000\nINPUT_BASE 04000000\nOUTPUT_BASE 05000000\n')
    desc = bytes(range(64))
    model = bytes(range(32)) * 40
    for name, base, data in [('desc', 0x80000, desc), ('model', 0x100000, model)]:
        text = f'@{base // 32:08x}\n'
        text += '\n'.join(data[i:i + 32][::-1].hex() for i in range(0, len(data), 32))
        (directory / f'mem_{name}.hex').write_text(text)
    return desc, model


class YoloTest(unittest.TestCase):
    def setUp(self):
        ready = patch('tools.debug_tool.core.ethernet.wait_for_link',
                      return_value=('loopback', 0.0))
        ready.start()
        self.addCleanup(ready.stop)

    def test_candidate_wire_and_enqueue_order(self):
        items = [([-256, 0, 25600, 12800], 8388608, 4, 3840),
                 ([0, 256, 512, 1024], 4194305, 79, 4800)]
        wire = pack_candidates(items)
        self.assertEqual(len(wire), 52)
        self.assertEqual(parse_candidates(wire)[0], (-256, 0, 25600, 12800,
                                                   8388608, 4, 3840))
        self.assertEqual(candidate_difference(wire, pack_candidates(items[::-1])),
                         dict(count=0, first=None))
        yolo = YoloTool(None)
        yolo.receive(0, 0, bytes(INPUT_BYTES), False)
        # Header and records can arrive out of order and split within a record.
        yolo.receive(1, 27, wire[27:], False)
        yolo.receive(1, 0, wire[:27], False)
        eddt = struct.pack('<4sHHII', b'EDDT', 1, 0, 123, 456)
        yolo.receive(2, 0, eddt, True)
        self.assertEqual(yolo.capture[1], wire)
        with self.assertRaisesRegex(ValueError, 'count/length'):
            parse_candidates(wire[:-1])

    def test_default_model_rebuilds_post_tables(self):
        ethernet = EthernetTool(local_ip="127.0.0.1")
        with (patch('tools.debug_tool.core.yolo.subprocess.run') as compile_model,
              patch('tools.debug_tool.core.yolo.pack_model', return_value=b'EDNM') as pack,
              patch.object(ethernet.showcase, 'bulk')):
            YoloTool(ethernet).send_model('', '127.0.0.1', 5000, 6000)
        self.assertIn('--model-source', compile_model.call_args.args[0])
        self.assertTrue(str(pack.call_args.args[0]).endswith('build/npu/software_model'))

    def test_rgb565_left_pixel_is_low_halfword(self):
        rgb = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255])
        data = rgb_to_rgb565(rgb)
        self.assertEqual(data, bytes.fromhex('00f8e0071f00ffff'))
        self.assertEqual(struct.unpack_from('<I', data)[0], 0x07e0f800)

    def test_compiler_hex_and_contiguous_ednm(self):
        with TemporaryDirectory() as directory:
            desc, model = compiler_fixture(directory)
            data = pack_model(directory)
        self.assertEqual(struct.unpack_from('<4s7I', data),
                         (b'EDNM', 1, 1, 64, 1280, 0x1000000, 0x4000000, 0x5000000))
        self.assertEqual(data[4096:4096 + len(desc)], desc)
        self.assertEqual(data[0x100000:], model)

    def test_model_bulk_contains_ednm_at_original_offsets(self):
        ethernet = EthernetTool(local_ip="127.0.0.1")
        with TemporaryDirectory() as directory:
            desc, model = compiler_fixture(directory)
            yolo = YoloTool(ethernet)
            with patch.object(ethernet.showcase, 'bulk') as bulk:
                yolo.send_model(directory, '127.0.0.1', 5000, 6000)
                kind, data, ip, port, local_port, name = bulk.call_args.args
                self.assertEqual((kind, ip, port, local_port), (1, '127.0.0.1', 5000, 6000))
                self.assertEqual(data[:4], b'EDNM')
                self.assertEqual(data[32:4096], bytes(4096 - 32))
                self.assertEqual(data[4096:4096 + len(desc)], desc)
                self.assertEqual(data[4096 + len(desc):0x100000],
                                 bytes(0x100000 - 4096 - len(desc)))
                self.assertEqual(data[0x100000:], model)
                self.assertEqual(yolo.image_bytes, 0x100000 + len(model))

    def test_scene_mapping_template_and_rate(self):
        class Engine:
            def send(self, command, ending):
                return command, ending
        scene = SceneControl(Engine())
        with patch.object(scene, 'mapping', return_value={
                'sample_rate': {'command': 'rate {rate}', 'ending': 'cr'},
                's1': {'command': None, 'ending': 'cr'}}):
            self.assertEqual(scene.send('sample_rate', 10), ('rate 10', 'cr'))
            self.assertEqual(scene.send('sample_rate', 1000), ('rate 1000', 'cr'))
            with self.assertRaisesRegex(ValueError, 'configure command'):
                scene.send('s1')
            with self.assertRaisesRegex(ValueError, '10..1000'):
                scene.send('sample_rate', 9)

    def test_scaled_image_dimensions_and_pixel_order(self):
        try:
            from PySide6.QtGui import QImage
        except ImportError:
            self.skipTest('PySide6 not installed in this Python; RGB565 wire test runs separately')
        from tools.debug_tool.core.yolo import image_rgb565
        with TemporaryDirectory() as directory:
            image = QImage(2, 1, QImage.Format_RGB888)
            image.setPixelColor(0, 0, 'red')
            image.setPixelColor(1, 0, 'blue')
            path = Path(directory) / 'input.png'
            self.assertTrue(image.save(str(path)))
            data = image_rgb565(path)
        self.assertEqual(len(data), 1280 * 720 * 2)
        self.assertEqual(data[:2], b'\0\0')
        self.assertEqual(data[(40*1280)*2:(40*1280)*2+2], bytes.fromhex('00f8'))
        self.assertEqual(data[(679*1280+1279)*2:(679*1280+1280)*2], bytes.fromhex('1f00'))
        self.assertEqual(data[-2:], b'\0\0')


class LetterboxTest(unittest.TestCase):
    def test_landscape_portrait_and_16_9_pixels_and_inverse_boxes(self):
        from PySide6.QtGui import QImage
        from tools.debug_tool.core.yolo import image_rgb565, letterbox_geometry, original_boxes
        for width, height, expected in ((1000, 500, (1280, 640, 0, 40)),
                                        (400, 800, (360, 720, 460, 0)),
                                        (1600, 900, (1280, 720, 0, 0))):
            with self.subTest(size=(width, height)), TemporaryDirectory() as directory:
                self.assertEqual(letterbox_geometry(width, height), expected)
                image = QImage(width, height, QImage.Format_RGB888)
                image.fill('red')
                path = Path(directory) / 'input.png'
                self.assertTrue(image.save(str(path)))
                data = image_rgb565(path)
                self.assertEqual(len(data), 1280 * 720 * 2)
                scaled_w, scaled_h, left, top = expected
                for x, y in ((0, 0), (1279, 719), (left, top),
                             (left + scaled_w - 1, top + scaled_h - 1)):
                    pixel = data[(y * 1280 + x)*2:(y * 1280 + x)*2+2]
                    inside = left <= x < left + scaled_w and top <= y < top + scaled_h
                    self.assertEqual(pixel, bytes.fromhex('00f8') if inside else b'\0\0')
                boxes = ((0, 0, 1280, 720, 3, 900),
                         (left + scaled_w/4, top + scaled_h/4,
                          left + scaled_w*3/4, top + scaled_h*3/4, 1, 800))
                self.assertEqual(original_boxes(boxes, width, height),
                                 ((0, 0, width, height, 3, 900),
                                  (width/4, height/4, width*3/4, height*3/4, 1, 800)))
                if left:
                    self.assertEqual(original_boxes(((0, 0, left, 720, 0, 1),),
                                                    width, height), ())
                if top:
                    self.assertEqual(original_boxes(((0, 0, 1280, top, 0, 1),),
                                                    width, height), ())
