"""test_yolo.py — B2 design 3.5a and SoC 4.5 transfer vectors; host clock domain."""

import json
from pathlib import Path
import struct
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from tools.debug_tool.core.ethernet import EthernetTool
from tools.debug_tool.core.scene import SceneControl
from tools.debug_tool.core.yolo import pack_model, rgb_to_rgb565, YoloTool


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
        self.assertEqual(data[:2], bytes.fromhex('00f8'))
        self.assertEqual(data[-2:], bytes.fromhex('1f00'))
