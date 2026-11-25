#!/usr/bin/env python3
"""Functional I8 light masks, coordinator-approved radial/Bayer construction.
Reuse only star indices unreferenced by the complete active effect library.
"""
import json
import math

from coast_assets import ASSETS
from coast_production import load_native_frames
from normalize_sample import expand, png
from texture_sample import color_word

PALETTE = 'coast-weapon-fx-star-06a2d-palette.json'
BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
LEVELS = 64


def rgba(word):
    return expand((word >> 11 & 31, word >> 5 & 63, word & 31, word >> 16 & 15))


def main():
    used = {0}
    for frame in load_native_frames():
        if frame['actor'] == 'coast_light':
            continue
        if (frame['palette_file'] == PALETTE
                or frame.get('palette_variants', {}).get('star') == PALETTE):
            source = json.loads((ASSETS / frame['palette_file']).read_text())
            lookup = {word: i for i, word in enumerate(source)}
            lookup[0] = 0
            used.update(lookup[color_word(p)] for p in frame['pixels'])
    palette = json.loads((ASSETS / PALETTE).read_text())
    palette += [0] * (256 - len(palette))
    original = list(palette)
    gray = [color_word((i * 255 // (LEVELS - 1),) * 3 + (255,))
            for i in range(LEVELS)]
    warm = [color_word((i * 255 // (LEVELS - 1), i * 210 // (LEVELS - 1),
                        i * 128 // (LEVELS - 1), 255)) for i in range(LEVELS)]
    white = color_word((255, 255, 255, 0))
    desired = list(dict.fromkeys(gray + warm + [white]))
    existing = {word: i for i, word in enumerate(palette)}
    existing[0] = 0
    assignment = {word: existing[word] for word in desired if word in existing}
    free = iter(i for i in range(256) if i not in used and i not in assignment.values())
    for word in desired:
        if word not in assignment:
            index = next(free)
            assignment[word] = index
            palette[index] = word
    reserved = sorted(set(assignment.values()) - used)
    pixels = [(0, 0, 0, 0)] * (128 * 64)
    for y in range(64):
        for x in range(64):
            radius = math.hypot(x - 31.5, y - 31.5) / 31.5
            threshold = (BAYER[y % 4][x % 4] + 0.5) / 16
            darkness = max(0.0, min(1.0, (radius - 0.32) / 0.68))
            level = min(LEVELS - 1, int((1 - darkness) * (LEVELS - 1) + threshold))
            lantern = white if radius < 0.32 else gray[level]
            glow = max(0.0, 1 - radius) ** 2
            glow_level = min(LEVELS - 1, int(glow * (LEVELS - 1) + threshold))
            pixels[y * 128 + x] = rgba(lantern)
            pixels[y * 128 + 64 + x] = rgba(warm[glow_level])
    name = 'coast-light-masks-06a2d'
    png(ASSETS / (name + '-native.png'), 128, 64, pixels)
    cells = []
    for i, action in enumerate(('lantern_view', 'light_zone')):
        cells.append({'id': f'down/{action}/0', 'cell': [i, 0], 'direction': 'down',
                      'action': action, 'frame': 0, 'anchor': [32, 32],
                      'hand_primary': None, 'filter': 'bilinear',
                      'blend': {'Fs': '0' if i == 0 else 'Sa',
                                'Fd': 'S' if i == 0 else '1', 'op': 'ADD'}})
    sheet = {'name': name, 'grid': [128, 64], 'cell': [64, 64], 'palette_file': PALETTE,
             'format': 1, 'atlas_group': 'coast_light', 'cells': cells}
    (ASSETS / (name + '-sheet.json')).write_text(json.dumps(sheet, indent=2) + '\n')
    layout = {'palette_file': PALETTE, 'levels': LEVELS,
              'protected_effect_indices': sorted(used),
              'protected_effect_words': {str(i): original[i] for i in sorted(used)},
              'light_resource_indices': sorted(set(assignment.values())),
              'light_reserved_indices': reserved,
              'light_reserved_words': {str(i): palette[i] for i in reserved},
              'gray_indices': [assignment[w] for w in gray],
              'warm_indices': [assignment[w] for w in warm],
              'transparent_white_index': assignment[white]}
    (ASSETS / PALETTE).write_text(json.dumps(palette) + '\n')
    (ASSETS / 'coast-light-palette-layout-06a2d.json').write_text(
        json.dumps(layout, indent=2) + '\n')
    path = ASSETS / 'production-06a2d.json'
    manifest = [s for s in json.loads(path.read_text()) if s['actor'] != 'coast_light']
    manifest.append({'actor': 'coast_light', 'metadata': name + '-sheet.json',
                     'actions': ['lantern_view', 'light_zone'], 'include_frames': True,
                     'normalize_source': False, 'cache': 'fixed', 'role': 'light'})
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Light masks: protected {len(used)} star indices, reserved {len(reserved)}, '
          f'2x4096 B, {LEVELS} levels and Bayer 4x4')


if __name__ == '__main__':
    main()
