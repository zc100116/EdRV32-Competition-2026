#!/usr/bin/env python3
"""test_pack.py: showcase design 4.5; package, PNG and ELF host regression.
All generated files reside in build/sw/game-pack; clock domain is host.
"""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import unittest
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/sw/game-pack'
spec = importlib.util.spec_from_file_location('pack_games', ROOT / 'tools/sw/pack_games.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack(
        '>I', zlib.crc32(kind + data))


def png_fixture(channels):
    width, height = 3, 5
    pixels = bytes((i * 31 + 17) % 256 for i in range(width * height * channels))
    rows = bytearray()
    stride = width * channels
    for y in range(height):
        row = pixels[y * stride:(y + 1) * stride]
        previous = pixels[(y - 1) * stride:y * stride] if y else bytes(stride)
        rows.append(y)  # one row for each of the five PNG filters
        for x, value in enumerate(row):
            left = row[x - channels] if x >= channels else 0
            above = previous[x]
            corner = previous[x - channels] if x >= channels else 0
            p = left + above - corner
            distances = (abs(p - left), abs(p - above), abs(p - corner))
            predictor = (0, left, above, (left + above) // 2,
                         (left, above, corner)[distances.index(min(distances))])[y]
            rows.append((value - predictor) & 255)
    header = struct.pack('>IIBBBBB', width, height, 8, 2 if channels == 3 else 6, 0, 0, 0)
    compressed = zlib.compress(rows)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
    png += chunk(b'IDAT', compressed[:7]) + chunk(b'IDAT', compressed[7:]) + chunk(b'IEND', b'')
    rgba = b''.join(pixels[i:i + 3] + (pixels[i + 3:i + 4] if channels == 4 else b'\xff')
                    for i in range(0, len(pixels), channels))
    return png, rgba


class GamePackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / 'icon.png').write_bytes(png_fixture(4)[0])
        (OUT / 'test.nes').write_bytes((ROOT / 'sw/apps/nes/roms/nrom-template.nes').read_bytes())
        (OUT / 'games.txt').write_text('测试游戏|test.nes|icon.png\n名字卡片|test.nes\n',
                                      encoding='utf-8')

    def test_png_decode_and_scale(self):
        for channels in (3, 4):
            with self.subTest(channels=channels):
                png, expected = png_fixture(channels)
                self.assertEqual(pack.decode_png(png), (3, 5, expected))
                icon = pack.png_icon(png)
                self.assertEqual(len(icon), 64 * 64 * 4)
                for y in range(64):
                    for x in range(64):
                        index = (y * 5 // 64 * 3 + x * 3 // 64) * 4
                        r, g, b, a = expected[index:index + 4]
                        self.assertEqual(icon[(y * 64 + x) * 4:(y * 64 + x + 1) * 4],
                                         bytes((b, g, r, a)))

    def test_pack_roundtrip(self):
        data = pack.build_pack(OUT)
        (OUT / 'games.bin').write_bytes(data)
        self.assertEqual(pack.HEADER.unpack_from(data), (b'EDGP', 1, 2))
        for i in range(2):
            fields = pack.ENTRY.unpack_from(data, 8 + i * 84)
            self.assertEqual(data[fields[1]:fields[1] + fields[2]],
                             (OUT / 'test.nes').read_bytes())
        first = pack.ENTRY.unpack_from(data, 8)
        self.assertEqual(data[first[3]:first[3] + 64 * 64 * 4],
                         pack.png_icon((OUT / 'icon.png').read_bytes()))
        subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        '-I' + str(ROOT / 'sw/apps/showcase/nes'),
                        str(ROOT / 'sw/tests/game_pack/parse.c'), '-o', str(OUT / 'parse')],
                       check=True)
        subprocess.run([str(OUT / 'parse'), str(OUT / 'games.bin')], check=True)

    def test_elf_segment(self):
        (OUT / 'stub.S').write_text('.global _start\n.text\n_start: j _start\n')
        (OUT / 'stub.ld').write_text('''ENTRY(_start)
SECTIONS {
  . = 0x90000000;
  .text : { *(.text) }
  .game_pack 0x92000000 (NOLOAD) : { . += 0x1000000; }
}
''')
        subprocess.run(['riscv-none-elf-gcc', '-march=rv32im', '-mabi=ilp32', '-nostdlib',
                        '-Wl,-T,' + str(OUT / 'stub.ld'), str(OUT / 'stub.S'),
                        '-o', str(OUT / 'showcase.elf')], check=True)
        subprocess.run([sys.executable, str(ROOT / 'tools/sw/pack_games.py'),
                        str(OUT / 'showcase.elf'), str(OUT), str(OUT / 'packed.elf')], check=True)
        data = (OUT / 'packed.elf').read_bytes()
        original = (OUT / 'showcase.elf').read_bytes()
        fields = struct.unpack_from('<16sHHIIIIIHHHHHH', data)
        phoff, phsize, phcount = fields[5], fields[9], fields[10]
        segments = [struct.unpack_from('<8I', data, phoff + phsize * i) for i in range(phcount)]
        loads = [p for p in segments if p[0] == 1]
        game_segment = next(p for p in loads if p[2] == 0x92000000)
        self.assertEqual(len([p for p in loads if p[2] == 0x92000000]), 1)
        blob = pack.build_pack(OUT)
        self.assertEqual(game_segment[3:], (0x92000000, len(blob), len(blob), 4, 4))
        self.assertEqual(data[game_segment[1]:game_segment[1] + game_segment[4]], blob)
        original_header = struct.unpack_from('<16sHHIIIIIHHHHHH', original)
        for i in range(original_header[10]):
            p = struct.unpack_from('<8I', original, original_header[5] + i * original_header[9])
            if p[0] == 1 and p[4]:
                self.assertEqual(original[p[1]:p[1] + p[4]], data[p[1]:p[1] + p[4]])
        result = subprocess.run(['riscv-none-elf-readelf', '-l', str(OUT / 'packed.elf')],
                                text=True, capture_output=True, check=True)
        (OUT / 'readelf.log').write_text(result.stdout)
        self.assertIn('0x92000000', result.stdout)
        self.assertIn(f'0x{len(blob):05x}', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
