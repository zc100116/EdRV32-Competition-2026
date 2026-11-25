#!/usr/bin/env python3
"""compact_coast_frames.py — tech 5b / gpu-spec 2.6 compact I8 DDR frames.
Host-only standard-library conversion. Complete four-bank groups are 4x2 texels;
the library is not a SET_TEX descriptor. Readback splices groups into legal pages.
"""
import json
import struct

from coast_assets import ASSETS, ROOT, normalize
from normalize_atlases import grid_centers
from normalize_sample import decode_png, palette_for
from probe_coast_streaming import cells
from texture_sample import color_word
from tools.gpu.model.layout import interleave_texture, texel_address
from tools.gpu.model.texture import Texture

BUILD = ROOT / 'build/ember_isles/art_coast_compact'
OUTPUT = ROOT / 'outputs/ember_isles/art3-coast-assets/06a2c'


def prepare_sources():
    sources = []
    for actor, stem in (
            ('tide_biter', 'tide-biter-down-06a2c'),
            ('salt_charger', 'salt-charger-down-06a2c-v2'),
            ('drowned_watcher', 'drowned-watcher-down-06a2c-v2'),
            ('mist_jellyfish', 'mist-jellyfish-down-06a2c')):
        width, height = 256, 128
        sw, sh, raw = decode_png((ASSETS / 'sources' / (stem + '-input.png')).read_bytes())
        xs, _ = grid_centers(raw, sw, sh, width, 0)
        ys, _ = grid_centers(raw, sw, sh, height, 1)
        pixels = []
        for y in ys:
            for x in xs:
                i = (y * sw + x) * 4
                pixels.append(tuple(raw[i:i + 3]) + (255,) if raw[i + 3] >= 192
                              else (0, 0, 0, 0))
        palette = [color_word(p) for p in palette_for(pixels, 255)]
        palette_file = stem + '-palette.json'
        (ASSETS / palette_file).write_text(json.dumps(palette) + '\n')
        sheet = {'name': stem, 'grid': [width, height], 'cell': [64, 64],
                 'palette_file': palette_file, 'palette_entries': len(palette),
                 'format': 1, 'atlas_group': actor, 'pixel_edits': [],
                 'row_edits': [], 'final_pixel_edits': [], 'foot_baseline': 58,
                 'cells': [{'id': f'{actor}/down/{action}/{frame}',
                            'cell': [frame, row], 'direction': 'down',
                            'action': action, 'frame': frame, 'anchor': [32, 58],
                            'hand_primary': None}
                           for row, action in enumerate(('idle', 'walk'))
                           for frame in range(4)]}
        metadata = stem + '-sheet.json'
        (ASSETS / metadata).write_text(json.dumps(sheet, indent=2) + '\n')
        _, measurement = normalize(sheet)
        sources.append({'actor': actor, 'metadata': metadata,
                        'actions': ['idle', 'walk'], 'measurement': measurement})
    sources.append({'actor': 'reef_crab', 'metadata': 'reef-crab-down-06a2-sheet.json',
                    'actions': ['idle', 'walk']})
    (ASSETS / 'coast-06a2c-sources.json').write_text(json.dumps(sources, indent=2) + '\n')


def load_frames():
    frames = []
    for item in json.loads((ASSETS / 'keeper-budget-sources.json').read_text()):
        sheet = json.loads((ASSETS / item['metadata']).read_text())
        actions = [a for a in item['actions'] if not a.startswith(('attack_', 'charge_'))]
        frames.extend(cells(sheet, actions, 'keeper'))
    sources = json.loads((ASSETS / 'coast-06a2c-sources.json').read_text())
    for item in sources:
        sheet = json.loads((ASSETS / item['metadata']).read_text())
        frames.extend(cells(sheet, item['actions'], item['actor']))
    return frames


def convert(frames, build=BUILD):
    palette_files = list(dict.fromkeys(f['palette_file'] for f in frames))
    palettes = [json.loads((ASSETS / p).read_text()) for p in palette_files]
    palettes = [p + [0] * (256 - len(p)) for p in palettes]
    blob, records = bytearray(), []
    readback_texels = 0
    for frame in frames:
        # gpu-spec 2.6: 2x2 halfwords per group; I8 halfwords hold 2x1 texels.
        width = (frame['w'] + 3) // 4 * 4
        height = (frame['h'] + 1) // 2 * 2
        bank = palette_files.index(frame['palette_file'])
        lookup = {word: i for i, word in enumerate(palettes[bank])}
        lookup[0] = 0
        indices = [0] * (width * height)
        for y in range(frame['h']):
            for x in range(frame['w']):
                indices[y * width + x] = lookup[color_word(frame['pixels'][y * frame['w'] + x])]
        packed = interleave_texture([indices], width, height, 1)
        blob.extend(bytes((-len(blob)) % 32))
        offset = len(blob)
        blob.extend(packed)
        records.append({k: v for k, v in frame.items()
                        if k not in ('pixels', 'palette_file')} |
                       {'ddr_offset': offset, 'bytes': len(packed),
                        'block_aligned_size': [width, height], 'palette_group': bank,
                        'format': 'I8', 'storage_group_texels': [4, 2]})
        # A compact frame is never sampled as an illegal non-power-of-two texture.
        # Copy its 8-byte groups to nonzero UV in a 128x128 page, OFFSET=32.
        page_width = 128 if width <= 124 else 256
        page_height = 128 if height <= 126 else 256
        u0, v0 = 4, 2
        page = bytearray(32 + page_width * page_height)
        for y in range(0, height, 2):
            for x in range(0, width, 4):
                source, _ = texel_address(x, y, width, height, 1, offset)
                destination, _ = texel_address(x + u0, y + v0,
                                               page_width, page_height, 1, 32)
                page[destination:destination + 8] = blob[source:source + 8]
        texture = Texture(page, palettes,
                          {'LOG2_W': page_width.bit_length() - 1,
                           'LOG2_H': page_height.bit_length() - 1, 'LEVELS': 1,
                           'FORMAT': 1, 'OFFSET': 32, 'PAL_GROUP': bank})
        for y in range(page_height):
            for x in range(page_width):
                sx, sy = x - u0, y - v0
                expected = (frame['pixels'][sy * frame['w'] + sx]
                            if 0 <= sx < frame['w'] and 0 <= sy < frame['h']
                            else (0, 0, 0, 0))
                actual = texture.texel(x, y, 0, bank)
                if actual != expected and not actual[3] == expected[3] == 0:
                    raise ValueError(f'{frame["name"]}: GPU page readback {x},{y}: '
                                     f'{actual} != {expected}')
                readback_texels += 1
    (build / 'frames.bin').write_bytes(blob)
    (build / 'palettes.bin').write_bytes(b''.join(struct.pack('<256I', *p) for p in palettes))
    return records, len(blob), readback_texels


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    prepare_sources()
    frames = load_frames()
    records, ddr_bytes, readback_texels = convert(frames)
    maxima = {}
    for record in records:
        actor = record['actor']
        maxima[actor] = max(maxima.get(actor, 0), record['bytes'])
    enemy_maxima = {k: v for k, v in maxima.items() if k != 'keeper'}
    measured_enemy_bound = 25 * sum(enemy_maxima.values())
    # The tide-biter draft exceeds tech 5b's small-swarm body range. Exclude it
    # from the capacity-failure proof instead of treating rejected art as valid.
    four_enemy_bound = 25 * sum(v for k, v in enemy_maxima.items() if k != 'tide_biter')
    result = {'scope': 'incomplete source checkpoint; sampled maxima are lower bounds',
              'format': 'I8 compact 4x2-texel groups, no power-of-two frame padding',
              'frames': records, 'ddr_library_bytes': ddr_bytes,
              'ddr_frame_payload_bytes': sum(r['bytes'] for r in records),
              'source_frames': len(records), 'palette_groups': len(set(
                  r['palette_group'] for r in records)),
              'gpu_readback_texels': readback_texels,
              'per_actor_max_bytes': maxima,
              'ordinary_enemy_actions': 5, 'ordinary_enemy_directions': 5,
              'sampled_five_enemy_bound_bytes': measured_enemy_bound,
              'cache_budget_bytes': 144 * 1024,
              'sampled_enemy_gap_bytes': max(0, measured_enemy_bound - 144 * 1024),
              'four_enemy_bound_excluding_oversize_tide_biter_bytes': four_enemy_bound,
              'four_enemy_gap_bytes': max(0, four_enemy_bound - 144 * 1024),
              'fixed_bytes': None, 'pet_bytes': None, 'elite_bytes': None,
              'scene_bytes': None, 'full_coast_bound_bytes': None}
    (BUILD / 'frames.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'PASS: {len(records)} compact frames, {readback_texels} GPU page texels')
    print(f'DDR partial {ddr_bytes} B; sampled maxima {maxima}')
    print(f'Sampled five-enemy synchronous bound {measured_enemy_bound} B / 147456 B')
    if four_enemy_bound > 144 * 1024:
        raise SystemExit(f'FAIL: four enemy kinds alone require at least {four_enemy_bound} B; '
                         f'gap {four_enemy_bound - 144 * 1024} B, production stopped')


if __name__ == '__main__':
    main()
