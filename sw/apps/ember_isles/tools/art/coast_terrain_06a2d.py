#!/usr/bin/env python3
"""coast_terrain_06a2d.py — art-plan4 native32px autotile composition.
Host-only standard library. Coordinator msg_da34df3aa4cb permits1:1 edge-band
copies and explicit1–2-row seam edits; no scaling, rotation or generated texture.
"""
import json
import random

from coast_assets import ASSETS
from coast_production import OUTPUT
from normalize_sample import decode_png, png

BIOMES = ('sand', 'shallow', 'reef', 'ruins', 'grass')
MASTER = 'coast-terrain-masters-06a2d'
VARIANTS = 'coast-terrain-variations-06a2d'
WATER = 'coast-shallow-flat-masters-06a2d'
BANDS = ((0, 0, 32, 8), (24, 0, 8, 32), (0, 24, 32, 8), (0, 0, 8, 32))


def tile(raw, width, column, row):
    return [tuple(raw[((row * 32 + y) * width + column * 32 + x) * 4:
                      ((row * 32 + y) * width + column * 32 + x) * 4 + 4])
            for y in range(32) for x in range(32)]


def seam(pixels):
    # Literal authored edge repairs remove the one-pixel generated cell divider.
    # Copying the immediately adjacent material row preserves its native texture.
    result = pixels[:]
    for y in range(32):
        result[y * 32 + 31] = result[y * 32 + 30]
    result[31 * 32:32 * 32] = result[30 * 32:31 * 32]
    return result


def insert(canvas, width, pixels, x0, y0):
    for y in range(32):
        canvas[(y0 + y) * width + x0:(y0 + y) * width + x0 + 32] = (
            pixels[y * 32:(y + 1) * 32])


def scaled(path, width, height, pixels, scale):
    png(path, width * scale, height * scale,
        [pixels[y // scale * width + x // scale]
         for y in range(height * scale) for x in range(width * scale)])


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mw, _, masters = decode_png((ASSETS / (MASTER + '-native.png')).read_bytes())
    vw, _, variants = decode_png((ASSETS / (VARIANTS + '-native.png')).read_bytes())
    ww, _, water = decode_png((ASSETS / (WATER + '-native.png')).read_bytes())
    package = ASSETS / 'production-06a2d.json'
    manifest = json.loads(package.read_text())
    manifest = [item for item in manifest
                if item['actor'] not in ['terrain_' + biome for biome in BIOMES]]
    recipes, all_tiles = [], []
    for row, biome in enumerate(BIOMES):
        sources = [seam(tile(masters, mw, column, row)) for column in range(5)]
        interiors = [seam(tile(variants, vw, column, row)) for column in range(4)]
        source_cells = [[column, row] for column in range(5)]
        source_name = MASTER
        if biome == 'shallow':
            sources = [seam(tile(water, ww, index % 3, index // 3)) for index in range(5)]
            interiors = [seam(tile(water, ww, index % 3, index // 3))
                         for index in range(5, 9)]
            source_cells = [[index % 3, index // 3] for index in range(5)]
            source_name = WATER
        frames = []
        for mask in range(16):
            pixels = sources[0][:]
            operations = [{'sheet': source_name, 'cell': source_cells[0],
                           'source': [0, 0, 32, 32], 'destination': [0, 0]}]
            for bit, (x0, y0, width, height) in enumerate(BANDS):
                if mask & (1 << bit):
                    continue
                source = sources[bit + 1]
                for y in range(y0, y0 + height):
                    pixels[y * 32 + x0:y * 32 + x0 + width] = (
                        source[y * 32 + x0:y * 32 + x0 + width])
                operations.append({'sheet': source_name, 'cell': source_cells[bit + 1],
                                   'source': [x0, y0, width, height],
                                   'destination': [x0, y0]})
            frames.append(pixels)
            recipes.append({'biome': biome, 'neighbor_mask_NESW': mask,
                            'operations': operations})
        frames.extend(interiors)
        all_tiles.append(frames)
        canvas = [(0, 0, 0, 0)] * (160 * 128)
        cells = []
        for index, pixels in enumerate(frames):
            x, y = index % 5, index // 5
            insert(canvas, 160, pixels, x * 32, y * 32)
            action, frame = ('autotile', index) if index < 16 else ('variation', index - 16)
            cells.append({'id': f'down/{action}/{frame}', 'cell': [x, y],
                          'direction': 'down', 'action': action, 'frame': frame,
                          'neighbor_mask_NESW': index if index < 16 else 15,
                          'anchor': [16, 16], 'hand_primary': None})
        stem = f'coast-{biome}-tiles-06a2d'
        png(ASSETS / (stem + '-native.png'), 160, 128, canvas)
        metadata = {'name': stem, 'grid': [160, 128], 'cell': [32, 32],
                    'palette_file': 'coast-terrain-06a2d-palette.json', 'format': 1,
                    'atlas_group': 'coast_terrain', 'cells': cells}
        (ASSETS / (stem + '-sheet.json')).write_text(json.dumps(metadata, indent=2) + '\n')
        manifest.append({'actor': 'terrain_' + biome, 'metadata': stem + '-sheet.json',
                         'actions': ['autotile', 'variation'], 'include_frames': True,
                         'normalize_source': False, 'cache': 'stream', 'role': 'terrain'})
        scaled(OUTPUT / (stem + '-8x.png'), 160, 128, canvas, 8)
        rng = random.Random(26 + row)
        sample = [(0, 0, 0, 0)] * (192 * 192)
        for y in range(6):
            for x in range(6):
                mask = ((y > 0) | (x < 5) << 1 | (y < 5) << 2 | (x > 0) << 3)
                frame = frames[16 + rng.randrange(4)] if mask == 15 else frames[mask]
                insert(sample, 192, frame, x * 32, y * 32)
        scaled(OUTPUT / ('terrain-' + biome + '-sample6x6-4x.png'), 192, 192, sample, 4)
    composition = {'permission': 'msg_da34df3aa4cb', 'native_tile_size': [32, 32],
                   'neighbor_bits': ['north', 'east', 'south', 'west'],
                   'seam_edits': [{'destination_column': 31, 'source_column': 30},
                                  {'destination_row': 31, 'source_row': 30}],
                   'rotation': False, 'flip': False, 'frames': recipes,
                   'variations': [{'biome': biome, 'sheet': VARIANTS, 'row': row,
                                   'columns': [0, 1, 2, 3]}
                                  for row, biome in enumerate(BIOMES)],
                   'shallow_variation_override': {'sheet': WATER,
                       'cells': [[i % 3, i // 3] for i in range(5, 9)]}}
    (ASSETS / 'coast-terrain-composition-06a2d.json').write_text(
        json.dumps(composition, indent=2) + '\n')
    package.write_text(json.dumps(manifest, indent=2) + '\n')
    before = [tile(masters, mw, 0, row) for row in range(5)]
    comparison = [(25, 38, 56, 255)] * (64 * 160)
    for row in range(5):
        insert(comparison, 64, before[row], 0, row * 32)
        insert(comparison, 64, all_tiles[row][15], 32, row * 32)
    scaled(OUTPUT / 'terrain-seam-before-after-8x.png', 64, 160, comparison, 8)
    print('Composed100 native32px tiles: 5biomes x(16NESW masks +4variations), no scaling')


if __name__ == '__main__':
    main()
