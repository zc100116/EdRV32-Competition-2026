"""test_yolo.py — B2 design 3.5a and SoC 4.5 transfer vectors; host clock domain."""

import json
from pathlib import Path
import socket
import struct
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from tools.debug_tool.core.ethernet import EthernetTool, unpack
from tools.debug_tool.core.scene import SceneControl
from tools.debug_tool.core.yolo import pack_model, rgb_to_rgb565, YoloTool
from test_program import wait_for


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
    def test_rgb565_left_pixel_is_low_halfword(self):
        rgb = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255])
        data = rgb_to_rgb565(rgb)
        self.assertEqual(data, bytes.fromhex('00f8e0071f00ffff'))
        self.assertEqual(struct.unpack_from('<I', data)[0], 0x07e0f800)

    def test_compiler_hex_and_ednm_sparse_blocks(self):
        with TemporaryDirectory() as directory:
            desc, model = compiler_fixture(directory)
            blocks = pack_model(directory)
        self.assertEqual([(w, o) for w, o, _ in blocks], [(2, 0), (2, 4096), (2, 0x100000)])
        self.assertEqual(struct.unpack('<4s7I', blocks[0][2]),
                         (b'EDNM', 1, 1, 64, 1280, 0x1000000, 0x4000000, 0x5000000))
        self.assertEqual(blocks[1][2], desc)
        self.assertEqual(blocks[2][2], model)

    def test_model_udp_exact_byte_count_and_only_final_notify(self):
        ethernet = EthernetTool(local_ip="127.0.0.1")
        with (TemporaryDirectory() as directory,
              socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock):
            compiler_fixture(directory)
            sock.bind(('127.0.0.1', 0))
            sock.settimeout(2)
            yolo = YoloTool(ethernet)
            yolo.send_model(directory, '127.0.0.1', sock.getsockname()[1], 0)
            received = [unpack(sock.recvfrom(65535)[0]) for _ in range(4)]
            wait_for(self, lambda: not ethernet.status()['tx']['active'])
            self.assertEqual([o for _, _, o, _ in received], [0, 4096, 0x100000, 0x100400])
            self.assertEqual([n for _, n, _, _ in received], [False, False, False, True])
            self.assertEqual(ethernet.status()['tx']['sent'], 32 + 64 + 1280)
            self.assertEqual(yolo.image_bytes, 1376)

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
