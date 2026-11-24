#!/usr/bin/env python3
"""texture_sample.py — gpu-spec §2.6/§2.11: measured ART-2 I8/I4 packing.
Host tool; use the unique bit reference tools/gpu/model/layout.py for swizzling.
Exports go to build/, not the game. Transparent margins are trimmed without scaling.
"""
import json
import struct
import sys

from normalize_sample import ASSETS, ROOT, decode_png, png

sys.path.insert(0, str(ROOT))
from tools.gpu.model.layout import mip_layout, texel_address

BUILD = ROOT / 'build/ember_isles/art_sample'
GROUPS = {
    'keeper': [('04-keeper-animation', 48, 48, [4, 6, 6]),
               ('09-directions', 48, 48, [6, 6])],
    'enemies': [('05-enemies', 64, 64, [5, 4, 5, 4])],
    'terrain': [('06-terrain', 64, 64, [7, 7, 7])],
    'props': [('07-props', 48, 64, [4, 3])],
    'effects': [('08-effects', 32, 32, [8, 8, 8, 4])],
}


def sprites_for(sheets):
    sprites = []
    for stem, cw, ch, counts in sheets:
        w, h, raw = decode_png((ASSETS / (stem + '-native.png')).read_bytes())
        p = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
        for row, count in enumerate(counts):
            for col in range(count):
                occupied = [(x, y) for y in range(ch) for x in range(cw)
                            if p[(row * ch + y) * w + col * cw + x][3]]
                x0, y0 = min(x for x, y in occupied), min(y for x, y in occupied)
                x1, y1 = max(x for x, y in occupied) + 1, max(y for x, y in occupied) + 1
                pixels = [p[(row * ch + y) * w + col * cw + x]
                          for y in range(y0, y1) for x in range(x0, x1)]
                sprites.append({'name': f'{stem}/{row}/{col}', 'w': x1 - x0,
                                'h': y1 - y0, 'trim': [x0, y0], 'pixels': pixels})
    return sorted(sprites, key=lambda s: (-s['h'], -s['w']))


def shelf(sprites, width, height):
    x, y, row_h = 0, 0, 0
    placed, remaining = [], []
    for sprite in sprites:
        sw, sh = sprite['w'], sprite['h']
        if sw > width or sh > height:
            remaining.append(sprite)
            continue
        if x + sw > width:
            x, y, row_h = 0, y + row_h, 0
        if y + sh > height:
            remaining.append(sprite)
            continue
        placed.append((sprite, x, y))
        x += sw
        row_h = max(row_h, sh)
    return placed, remaining


def color_word(p):
    return ((p[3] // 17) << 16 | (p[0] >> 3) << 11 | (p[1] >> 2) << 5 | p[2] >> 3)


def export_group(name, sprites):
    words = sorted({color_word(p) for s in sprites for p in s['pixels'] if p[3]})
    palette = [0] + words
    lookup = {word: i for i, word in enumerate(palette)}
    fmt = 0 if len(palette) <= 16 else 1
    (BUILD / (name + '.pal')).write_bytes(b''.join(struct.pack('<I', v)
                                                   for v in palette + [0] * (256 - len(palette))))
    pages = []
    remaining = sprites
    while remaining:
        candidates = []
        for width in (8, 16, 32, 64, 128, 256):
            for height in (8, 16, 32, 64, 128, 256):
                placed, rest = shelf(remaining, width, height)
                if not rest:
                    candidates.append((width * height, width, height, placed))
        if candidates:
            _, width, height, placed = min(candidates, key=lambda c: c[:3])
            remaining = []
        else:
            width, height = 256, 256
            placed, remaining = shelf(remaining, width, height)
        pixels = [(0, 0, 0, 0)] * (width * height)
        records = []
        for sprite, x, y in placed:
            for j in range(sprite['h']):
                start = (y + j) * width + x
                source_row = sprite['pixels'][j * sprite['w']:(j + 1) * sprite['w']]
                pixels[start:start + sprite['w']] = source_row
            records.append({'name': sprite['name'], 'xy': [x, y],
                            'size': [sprite['w'], sprite['h']], 'trim': sprite['trim']})
        size = mip_layout(width, height, 1, fmt, 0)[0][3]
        packed = bytearray(size)
        for y in range(height):
            for x in range(width):
                p = pixels[y * width + x]
                index = lookup[color_word(p)] if p[3] else 0
                address, bit = texel_address(x, y, width, height, fmt, 0)
                value = int.from_bytes(packed[address:address + 2], 'little')
                packed[address:address + 2] = (value | index << bit).to_bytes(2, 'little')
        number = len(pages)
        (BUILD / f'{name}-{number}.bin').write_bytes(packed)
        png(BUILD / f'{name}-{number}.png', width, height, pixels)
        pages.append({'size': [width, height], 'bytes': size, 'sprites': records})
    return {'name': name, 'format': 'I4' if fmt == 0 else 'I8', 'sprites': len(sprites),
            'colors': len(palette), 'palette_bytes': 1024, 'pages': pages,
            'texture_bytes': sum(p['bytes'] for p in pages)}


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    groups = [export_group(name, sprites_for(sheets)) for name, sheets in GROUPS.items()]
    # A4 radial alpha is a native I4 mask: sixteen transparency levels, fixed RGB565.
    mask = []
    for y in range(128):
        for x in range(128):
            alpha = round(max(0, 1 - (((x - 63.5) ** 2 + (y - 63.5) ** 2) ** .5) / 64) * 15)
            mask.append((255, 255, 255, alpha * 17))
    png(ASSETS / '12-light-mask.png', 128, 128, mask)
    groups.append(export_group('light-mask', [{'name': 'A4-radial', 'w': 128, 'h': 128,
                                              'trim': [0, 0], 'pixels': mask}]))
    texture = sum(g['texture_bytes'] for g in groups)
    palettes = sum(g['palette_bytes'] for g in groups)
    # Full coast estimate: one selected character; all five small enemies; one boss.
    estimate = {'keeper_48x24x40': 48 * 24 * 40,
                'five_enemies_17x56x40': 5 * 17 * 56 * 40,
                'boss_24x96x96': 24 * 96 * 96,
                'terrain_64x64x64': 64 * 64 * 64,
                'props_20x32x48': 20 * 32 * 48,
                'effects_48x32x32': 48 * 32 * 32,
                'hud_and_font': 16384, 'radial_i4': 8192}
    result = {'groups': groups, 'texture_bytes': texture, 'palette_bytes': palettes,
              'combined_bytes': texture + palettes, 'fpga_texture_limit': 192 * 1024,
              'pc_texture_limit': 256 * 1024, 'full_coast_i8_area_estimate': estimate,
              'full_coast_area_total': sum(estimate.values()),
              'full_coast_with_20_percent_packing_estimate': round(sum(estimate.values()) * 1.2),
              'upgrade_full_bitmap_i8_separate_screen': 640 * 384,
              'note': 'Palettes are separate GPU palette RAM; do not subtract from texture RAM.'}
    (ASSETS / 'texture-measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    for g in groups:
        print(g['name'], g['format'], g['sprites'], 'sprites', g['colors'], 'colors',
              [p['size'] for p in g['pages']], g['texture_bytes'], 'texture bytes')
    print('Texture', texture, 'Palette', palettes, 'Combined', texture + palettes)
    print('Full coast area estimate', sum(estimate.values()), 'bytes; +20% packing',
          round(sum(estimate.values()) * 1.2))


if __name__ == '__main__':
    main()
