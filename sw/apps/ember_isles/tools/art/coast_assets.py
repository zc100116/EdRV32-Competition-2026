#!/usr/bin/env python3
"""coast_assets.py — tech 5b/7: normalize ART-3 sheets and measure GPU pages.
Host-only, standard library. Source clusters are sampled on their declared grid;
no actor drawing, silhouette scaling, animation synthesis or format fallback.
"""
import json
import struct
import sys

from normalize_sample import ROOT, decode_png, expand, png
from normalize_atlases import grid_centers
from texture_sample import shelf, color_word

sys.path.insert(0, str(ROOT))
from tools.gpu.model.layout import interleave_texture, mip_layout
from tools.gpu.model.texture import Texture

ASSETS = ROOT / 'sw/apps/ember_isles/assets/art_coast'
BUILD = ROOT / 'build/ember_isles/art_coast'
OUTPUT = ROOT / 'outputs/ember_isles/art3-coast-assets'
DIRECTIONS = ('down', 'down_right', 'right', 'up_right', 'up')


def normalize(sheet):
    name = sheet['name']
    width, height = sheet['grid']
    sw, sh, raw = decode_png((ASSETS / 'sources' / (name + '-input.png')).read_bytes())
    xs, pitch_x = grid_centers(raw, sw, sh, width, 0)
    ys, pitch_y = grid_centers(raw, sw, sh, height, 1)
    pixels = []
    for y in ys:
        for x in xs:
            i = (y * sw + x) * 4
            p = tuple(raw[i:i + 4])
            pixels.append((*p[:3], 255) if p[3] >= 192 else (0, 0, 0, 0))
    # Each correction is an explicit reviewed logical-pixel edit, not pose synthesis.
    for edit in sheet['pixel_edits']:
        x, y = edit['xy']
        pixels[y * width + x] = tuple(edit['rgba'])
    words = json.loads((ASSETS / sheet['palette_file']).read_text())[:sheet['palette_entries']]
    palette = [expand((v >> 11 & 31, v >> 5 & 63, v & 31, v >> 16 & 15))
               for v in words]
    mapping = {(0, 0, 0, 0): (0, 0, 0, 0)}
    for p in set(pixels):
        if p[3]:
            mapping[p] = min(palette[1:], key=lambda c: sum(
                (p[k] - c[k]) ** 2 for k in range(3)))
    pixels = [mapping[p] for p in pixels]
    cw, ch = sheet['cell']
    if 'foot_baseline' in sheet:
        original = pixels[:]
        for cell in sheet['cells']:
            cx, cy = cell['cell']
            points = [(x, y) for y in range(ch) for x in range(cw)
                      if original[(cy * ch + y) * width + cx * cw + x][3]]
            bottom = max(y for x, y in points)
            shift_y = sheet['foot_baseline'] - bottom
            if min(y for x, y in points) + shift_y < 0:
                raise ValueError(f'{name}/{cell["id"]}: foot alignment would crop the sprite')
            for y in range(ch):
                for x in range(cw):
                    sy = y - shift_y
                    pixels[(cy * ch + y) * width + cx * cw + x] = (
                        original[(cy * ch + sy) * width + cx * cw + x]
                        if 0 <= sy < ch else (0, 0, 0, 0))
    png(ASSETS / (name + '-before-repair.png'), width, height, pixels)
    # Replay authored 1–2-row material-seam repairs, identically for each facing.
    # The explicit row list is artwork, never derived from silhouette size.
    for edit in sheet.get('row_edits', []):
        cx, cy = edit['cell']
        rows = [[pixels[(cy * ch + y) * width + cx * cw + x] for x in range(cw)]
                for y in edit['rows']]
        for y, row in enumerate(rows):
            pixels[(cy * ch + y) * width + cx * cw:
                   (cy * ch + y) * width + (cx + 1) * cw] = row
    for edit in sheet.get('final_pixel_edits', []):
        x, y = edit['xy']
        pixels[y * width + x] = tuple(edit['rgba'])
    png(ASSETS / (name + '-native.png'), width, height, pixels)
    png(OUTPUT / (name + '-8x.png'), width * 8, height * 8,
        [pixels[y // 8 * width + x // 8]
         for y in range(height * 8) for x in range(width * 8)])
    sprites = []
    for cell in sheet['cells']:
        cx, cy = cell['cell']
        occupied = [(x, y) for y in range(ch) for x in range(cw)
                    if pixels[(cy * ch + y) * width + cx * cw + x][3]]
        x0, y0 = min(x for x, y in occupied), min(y for x, y in occupied)
        x1, y1 = max(x for x, y in occupied) + 1, max(y for x, y in occupied) + 1
        content = [pixels[(cy * ch + y) * width + cx * cw + x]
                   for y in range(y0, y1) for x in range(x0, x1)]
        sprites.append({**cell, 'name': name + '/' + cell['id'],
                        'w': x1 - x0, 'h': y1 - y0, 'trim': [x0, y0],
                        'pixels': content})
    actions = {}
    for sprite in sprites:
        key = sprite['direction'] + '/' + sprite['action']
        actions.setdefault(key, [])
        # Compare actual pixel tuples, without hashes or frame-count assumptions.
        content = (sprite['w'], sprite['h'], sprite['pixels'])
        if content not in actions[key]:
            actions[key].append(content)
    return sprites, {'name': name, 'source_size': [sw, sh], 'grid': [width, height],
                     'pitch': [pitch_x, pitch_y], 'colors': len(palette),
                     'distinct_frames': {k: len(v) for k, v in actions.items()},
                     'bounds': [{'id': s['id'], 'size': [s['w'], s['h']],
                                 'trim': s['trim']} for s in sprites]}


def pack(name, sprites, fmt, palette_file):
    palette = json.loads((ASSETS / palette_file).read_text())
    used = {color_word(p) for s in sprites for p in s['pixels'] if p[3]}
    lookup = {word: i for i, word in enumerate(palette)}
    limit = 16 if fmt == 0 else 256
    maximum = max(lookup[word] for word in used)
    if maximum >= limit:
        raise ValueError(f'{name}: palette index {maximum} exceeds format limit {limit - 1}')
    (BUILD / (name + '.pal')).write_bytes(struct.pack(
        '<256I', *(palette + [0] * (256 - len(palette)))))
    remaining = sorted(sprites, key=lambda s: (-s['h'], -s['w']))
    pages = []
    offset = 0
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
            width = height = 256
            placed, remaining = shelf(remaining, width, height)
        pixels = [(0, 0, 0, 0)] * (width * height)
        records = []
        for sprite, x, y in placed:
            for j in range(sprite['h']):
                pixels[(y + j) * width + x:(y + j) * width + x + sprite['w']] = (
                    sprite['pixels'][j * sprite['w']:(j + 1) * sprite['w']])
            records.append({k: v for k, v in sprite.items() if k != 'pixels'} | {'xy': [x, y]})
        indices = [lookup[color_word(p)] if p[3] else 0 for p in pixels]
        packed = interleave_texture([indices], width, height, fmt)
        number = len(pages)
        stem = f'{name}-{number}'
        (BUILD / (stem + '.bin')).write_bytes(packed)
        png(BUILD / (stem + '.png'), width, height, pixels)
        # Acceptance requires the real GPU reference's palette and texel read path.
        texture = Texture(packed, [palette], {'LOG2_W': width.bit_length() - 1,
            'LOG2_H': height.bit_length() - 1, 'LEVELS': 1, 'FORMAT': fmt,
            'OFFSET': 0, 'PAL_GROUP': 0})
        for y in range(height):
            for x in range(width):
                actual, expected = texture.texel(x, y, 0, 0), pixels[y * width + x]
                if actual != expected and not (actual[3] == expected[3] == 0):
                    raise ValueError(f'{stem}: GPU texel mismatch at {x},{y}')
        size = mip_layout(width, height, 1, fmt)[0][3]
        offset = (offset + 31) // 32 * 32
        pages.append({'file': stem + '.bin', 'offset': offset, 'bytes': size,
                      'size': [width, height], 'sprites': records})
        offset += size
    return {'name': name, 'format': fmt, 'palette_entries': len(palette),
            'palette_file': palette_file, 'used_colors': len(used) + 1,
            'palette_bytes': 1024, 'texture_bytes': offset, 'pages': pages}


def export_catalog(groups):
    """CPU source container; package tables assign actual GPU offsets and banks."""
    texture = bytearray()
    palettes, pages, sprites = [], [], []
    for group in groups:
        palette = list(struct.unpack('<256I',
            (BUILD / (group['name'] + '.pal')).read_bytes()))
        if palette not in palettes:
            palettes.append(palette)
        palette_id = palettes.index(palette)
        group['palette_resource'] = palette_id
        for page in group['pages']:
            texture.extend(bytes((-len(texture)) % 32))
            offset = len(texture)
            texture.extend((BUILD / page['file']).read_bytes())
            page_id = len(pages)
            width, height = page['size']
            pages.append([offset, page['bytes'], width.bit_length() - 1,
                          height.bit_length() - 1, group['format'], palette_id])
            for sprite in page['sprites']:
                hand = sprite['hand_primary']
                hand_x, hand_y = (-1, -1) if hand is None else hand
                sprites.append([sprite['name'], page_id, *sprite['xy'],
                                sprite['w'], sprite['h'], *sprite['trim'],
                                *sprite['anchor'], hand_x, hand_y])
    (BUILD / 'catalog.bin').write_bytes(texture)
    header = ['/* Generated ART-3 CPU asset source; not a GPU resident configuration. */',
              '#ifndef EMBER_ISLES_COAST_CATALOG_H', '#define EMBER_ISLES_COAST_CATALOG_H',
              '#include <stdint.h>',
              f'#define COAST_TEXTURE_BYTES {len(texture)}u',
              f'#define COAST_PALETTE_COUNT {len(palettes)}u',
              f'#define COAST_PAGE_COUNT {len(pages)}u',
              f'#define COAST_SPRITE_COUNT {len(sprites)}u',
              'typedef struct {',
              '    uint32_t cpu_offset, bytes;',
              '    uint8_t log2_w, log2_h, format, palette_resource;',
              '} coast_page;',
              'typedef struct {',
              '    const char *name;',
              '    uint16_t page, u, v, w, h;',
              '    int16_t trim_x, trim_y, anchor_x, anchor_y, hand_x, hand_y;',
              '} coast_sprite;',
              'extern const uint8_t coast_texture[COAST_TEXTURE_BYTES];',
              'extern const uint32_t coast_palettes[COAST_PALETTE_COUNT][256];',
              'extern const coast_page coast_pages[COAST_PAGE_COUNT];',
              'extern const coast_sprite coast_sprites[COAST_SPRITE_COUNT];', '#endif']
    (BUILD / 'catalog.h').write_text('\n'.join(header) + '\n')
    source = ['/* Generated ART-3 CPU source; select a measured package before TEX_LOAD. */',
              '#include "catalog.h"',
              '_Alignas(32) const uint8_t coast_texture[COAST_TEXTURE_BYTES] = {']
    source.extend('    ' + ','.join(f'0x{v:02x}' for v in texture[i:i + 16]) + ','
                  for i in range(0, len(texture), 16))
    source += ['};', '_Alignas(32) const uint32_t coast_palettes[COAST_PALETTE_COUNT][256] = {']
    for palette in palettes:
        source.append('    {')
        source.extend('        ' + ','.join(f'0x{v:05x}' for v in palette[i:i + 8]) + ','
                      for i in range(0, 256, 8))
        source.append('    },')
    source += ['};', 'const coast_page coast_pages[COAST_PAGE_COUNT] = {']
    source.extend('    {' + ','.join(str(v) for v in page) + '},' for page in pages)
    source += ['};', 'const coast_sprite coast_sprites[COAST_SPRITE_COUNT] = {']
    source.extend('    {' + json.dumps(sprite[0]) + ','
                  + ','.join(str(v) for v in sprite[1:]) + '},' for sprite in sprites)
    source += ['};']
    (BUILD / 'catalog.c').write_text('\n'.join(source) + '\n')


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ASSETS / 'sheets.json').read_text())
    measurements, source_groups = [], {}
    for sheet in manifest:
        sprites, measured = normalize(sheet)
        measurements.append(measured)
        group = sheet['atlas_group']
        if group not in source_groups:
            source_groups[group] = {'format': sheet['format'], 'sprites': [],
                                    'palette_file': sheet['palette_file']}
        source_groups[group]['sprites'].extend(sprites)
    groups = [pack(name, group['sprites'], group['format'], group['palette_file'])
              for name, group in source_groups.items()]
    export_catalog(groups)
    result = {'sheets': measurements, 'groups': groups,
              'scope': 'Only saved source sheets; incomplete scope is not a resident configuration',
              'half_limit_bytes': 98304, 'palette_group_limit': 16}
    (BUILD / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
