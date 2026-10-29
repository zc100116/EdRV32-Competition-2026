#!/usr/bin/env python3
# File: game_assets.py
# Spec: rnd 2.1/2.6; Task B3-3b game resources.
# Description: Original pixel art, level and glyphs, emitted as aligned DDR C arrays.
# Clock domain: host generator.
"""Generate game resources into build/s3/game, using only the Python standard library."""
from pathlib import Path
import struct

OUT = Path('build/s3/game')
WIDTH = 320
HEIGHT = 45


def resources():
    palette = [0x00000000, 0xff142e48, 0xfff5cc68, 0xffe66b50,
               0xfff5eed6, 0xff4aa38c, 0xff246557, 0xff836044,
               0xff536586, 0xffa5d6dd, 0xffb8e5e7, 0xffcf9d62,
               0xff2e455b, 0xffebac39, 0xff9477b7, 0xff667f92]
    tiles = []
    for kind in range(8):
        for y in range(16):
            for x in range(16):
                value = 9
                if kind == 1:
                    value = 5 if y < 4 else 7 if (x + y * 3) % 17 < 3 else 11
                elif kind == 2:
                    value = 12 if x in (0, 15) or y in (0, 15) else 8
                elif kind == 3:
                    value = 10 if (x - 8) ** 2 + (y - 10) ** 2 < 65 else 9
                elif kind == 4:
                    value = 5 if x < y else 9
                elif kind == 5:
                    value = 6 if y > 7 else 5
                elif kind == 6:
                    value = 4 if x in (7, 8) else 9
                elif kind == 7:
                    value = 3 if x > 8 and y < 10 else 4 if x in (7, 8) else 9
                tiles.append(value)
    level = [0] * (WIDTH * HEIGHT)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            tile = 0
            if y >= 39:
                tile = 1 if y == 39 else 2
            # Two 96-pixel gaps; land on the far bank after jumping.
            if x in range(88, 94) or x in range(213, 219):
                if y >= 39:
                    tile = 0
            if 132 <= x < 138 and 37 <= y < 39:
                tile = 2
            if y in (9, 10) and (x % 43) in (6, 7, 8, 9):
                tile = 3
            if 29 <= y < 39 and (x % 57) < y - 28 and tile == 0:
                tile = 4
            if x == 310 and 29 <= y < 39:
                tile = 7 if y == 29 else 6
            level[y * WIDTH + x] = tile
    sprites = []
    for kind in range(6):
        for y in range(24):
            for x in range(16):
                value = 0
                if kind in (0, 1):
                    if 3 <= x <= 12 and 2 <= y <= 8:
                        value = 2 if y > 4 else 3
                    if 4 <= x <= 11 and 9 <= y <= 17:
                        value = 3 if x < 8 else 4
                    if 2 <= x <= 13 and 11 <= y <= 13:
                        value = 2
                    if 17 <= y <= 22 and (x in (4, 5, 6) or x in (10, 11, 12)):
                        value = 1
                    if kind == 1 and y > 20 and x < 8:
                        value = 0
                    if x == 11 and y == 5:
                        value = 1
                elif kind == 2:  # Patrol beetle.
                    if (x - 8) ** 2 + (y - 15) ** 2 < 54:
                        value = 14 if y < 15 else 1
                    if y in (20, 21) and x % 4 < 2:
                        value = 1
                    if y == 13 and x in (10, 11):
                        value = 4
                elif kind == 3:  # Spike obstacle.
                    if 8 <= y <= 22 and abs(x - 8) <= (y - 6) // 2:
                        value = 4 if x < 8 else 8
                elif kind == 4:  # Amber collectible.
                    if ((x - 8) / 6) ** 2 + ((y - 12) / 10) ** 2 < 1:
                        value = 13 if x > 7 else 2
                    if x in (7, 8) and 6 <= y <= 17:
                        value = 4
                elif kind == 5:  # Flag icon for HUD.
                    if x in (3, 4) and 2 <= y <= 22:
                        value = 4
                    if 5 <= x <= 13 and 2 <= y <= 10:
                        value = 5
                sprites.append(value)
    patterns = {
        ' ': '00000/00000/00000/00000/00000/00000/00000',
        '0': '01110/10001/10011/10101/11001/10001/01110',
        '1': '00100/01100/00100/00100/00100/00100/01110',
        '2': '01110/10001/00001/00010/00100/01000/11111',
        '3': '11110/00001/00001/01110/00001/00001/11110',
        '4': '00010/00110/01010/10010/11111/00010/00010',
        '5': '11111/10000/10000/11110/00001/00001/11110',
        '6': '01110/10000/10000/11110/10001/10001/01110',
        '7': '11111/00001/00010/00100/01000/01000/01000',
        '8': '01110/10001/10001/01110/10001/10001/01110',
        '9': '01110/10001/10001/01111/00001/00001/01110',
        'A': '01110/10001/10001/11111/10001/10001/10001',
        'B': '11110/10001/10001/11110/10001/10001/11110',
        'C': '01111/10000/10000/10000/10000/10000/01111',
        'D': '11110/10001/10001/10001/10001/10001/11110',
        'E': '11111/10000/10000/11110/10000/10000/11111',
        'F': '11111/10000/10000/11110/10000/10000/10000',
        'G': '01111/10000/10000/10111/10001/10001/01111',
        'H': '10001/10001/10001/11111/10001/10001/10001',
        'I': '01110/00100/00100/00100/00100/00100/01110',
        'J': '00001/00001/00001/00001/10001/10001/01110',
        'K': '10001/10010/10100/11000/10100/10010/10001',
        'L': '10000/10000/10000/10000/10000/10000/11111',
        'M': '10001/11011/10101/10101/10001/10001/10001',
        'N': '10001/11001/10101/10011/10001/10001/10001',
        'O': '01110/10001/10001/10001/10001/10001/01110',
        'P': '11110/10001/10001/11110/10000/10000/10000',
        'Q': '01110/10001/10001/10001/10101/10010/01101',
        'R': '11110/10001/10001/11110/10100/10010/10001',
        'S': '01111/10000/10000/01110/00001/00001/11110',
        'T': '11111/00100/00100/00100/00100/00100/00100',
        'U': '10001/10001/10001/10001/10001/10001/01110',
        'V': '10001/10001/10001/10001/10001/01010/00100',
        'W': '10001/10001/10001/10101/10101/10101/01010',
        'X': '10001/10001/01010/00100/01010/10001/10001',
        'Y': '10001/10001/01010/00100/00100/00100/00100',
        'Z': '11111/00001/00010/00100/01000/10000/11111',
    }
    glyphs = []
    for c in ' 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ':
        rows = patterns[c].split('/')
        glyphs.extend(255 * int(rows[y // 3][x // 3]) for y in range(21) for x in range(15))
    spike_rgb565 = []
    for index in sprites[3 * 16 * 24:4 * 16 * 24]:
        color = palette[index]
        spike_rgb565.append(0xf81f if index == 0 else
                            (((color >> 19) & 31) << 11) |
                            (((color >> 10) & 63) << 5) | ((color >> 3) & 31))
    return [('game_palette' , 'uint32_t', palette, 4),
            ('game_tiles', 'uint8_t', tiles, 1),
            ('game_map', 'uint16_t', level, 2),
            ('game_sprites', 'uint8_t', sprites, 1),
            ('game_spike_rgb565', 'uint16_t', spike_rgb565, 2),
            ('game_glyphs', 'uint8_t', glyphs, 1)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    header = ['/* Generated by tools/s3/game_assets.py; original project artwork. */',
              '#ifndef S3_GAME_ASSETS_H', '#define S3_GAME_ASSETS_H', '#include <stdint.h>']
    source = ['/* Generated by tools/s3/game_assets.py; DDR resources. */',
              '#include "game_assets.h"']
    for name, ctype, values, size in resources():
        header.append(f'extern const {ctype} {name}[{len(values)}];')
        source.append(f'_Alignas(32) const {ctype} {name}[{len(values)}] = {{')
        for i in range(0, len(values), 16):
            source.append('    ' + ', '.join(f'0x{v:0{size * 2}x}' for v in values[i:i+16]) + ',')
        source.append('};')
        (OUT / f'{name}.bin').write_bytes(b''.join(struct.pack({1:'<B',2:'<H',4:'<I'}[size], v)
                                                for v in values))
    header.append('#endif')
    (OUT / 'game_assets.h').write_text('\n'.join(header) + '\n')
    (OUT / 'game_assets.c').write_text('\n'.join(source) + '\n')
    print(f'Generated original game resources in {OUT}')


if __name__ == '__main__':
    main()
