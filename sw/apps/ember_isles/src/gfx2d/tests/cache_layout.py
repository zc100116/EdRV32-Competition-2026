#!/usr/bin/env python3
"""Verify actual I4 auras beside I8 frames in one byte page with the sole GPU model.
The runtime uses eight-byte blocks, with two/four texel rows per I8/I4 block.
"""
import json
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[6]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT))
from tools.gpu.model.arithmetic import expand
from tools.gpu.model.layout import texel_address
from tools.gpu.model.texture import Texture


def main():
    pack = ROOT / 'build/ember_isles/art_coast_production'
    table = json.loads((pack / 'pc-frames.json').read_text())
    blob = (pack / table['ddr_library']).read_bytes()
    words = struct.unpack('<' + 'I' * ((pack / 'palettes.bin').stat().st_size // 4),
                          (pack / 'palettes.bin').read_bytes())
    palettes = [words[i:i + 256] for i in range(0, len(words), 256)]
    auras = [f for f in table['frames'] if f['action'].startswith('elite_aura_')]
    assert len({f['action'] for f in auras}) == 8
    assert all(f['format'] == 'I4' for f in auras)
    companion = next(f for f in table['frames'] if f['format'] == 'I8' and
                     f['block_aligned_size'][0] <= 32 and f['block_aligned_size'][1] <= 32)
    checked = 0
    for aura in auras:
        ram = bytearray(16384)
        placed = [(aura, 4, 4), (companion, 4 + aura['block_aligned_size'][0], 2)]
        for frame, u0, v0 in placed:
            fmt = {'I4': 0, 'I8': 1}[frame['format']]
            block_h = 2 if fmt else 4
            width, height = frame['block_aligned_size']
            for row in range(height // block_h):
                start = frame['ddr_offset'] + row * width * 2
                dest = (v0 // block_h + row) * 128 * 2 + u0 * 2
                ram[dest:dest + width * 2] = blob[start:start + width * 2]
        for frame, u0, v0 in placed:
            fmt = {'I4': 0, 'I8': 1}[frame['format']]
            width, height = frame['block_aligned_size']
            texture = Texture(ram, palettes, {'LOG2_W': 7, 'LOG2_H': 7 if fmt else 8,
                              'LEVELS': 1, 'FORMAT': fmt, 'OFFSET': 0})
            groups = {frame['palette_group'], *frame['palette_variants'].values()}
            for group in groups:
                for y in range(frame['h']):
                    for x in range(frame['w']):
                        address, bit = texel_address(x, y, width, height, fmt, frame['ddr_offset'])
                        value = int.from_bytes(blob[address:address + 2], 'little')
                        index = value >> bit & (255 if fmt else 15)
                        color = palettes[group][index]
                        expected = (*expand(color & 65535), (color >> 16 & 15) * 17)
                        assert texture.texel(u0 + x, v0 + y, 0, group) == expected
                        checked += 1
    print(f'PASS mixed byte pages: I4 aura frames={len(auras)}, I8 companions={len(auras)}, '
          f'GPU-model texels={checked}, nonzero UV, all declared palettes')


if __name__ == '__main__':
    main()
