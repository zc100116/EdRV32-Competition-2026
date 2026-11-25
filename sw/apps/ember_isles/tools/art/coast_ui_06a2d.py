#!/usr/bin/env python3
"""coast_ui_06a2d.py — art-plan7 / first-release four-rarity card borders.
Host-only standard library. Extract native8px corners/edge strips without
resizing source artwork; the transparent center consumes no texture storage.
"""
import json

from coast_assets import ASSETS
from normalize_sample import png
from probe_coast_streaming import cells


def main():
    source = json.loads((ASSETS / 'coast-card-frames-06a2d-sheet.json').read_text())
    rarities = ('common', 'fine', 'rare', 'legendary')
    cards = cells(source, rarities, 'coast_card_source')
    canvas = [(0, 0, 0, 0)] * (64 * 32)
    records, layouts = [], []
    names = ('top_left', 'top_right', 'bottom_left', 'bottom_right',
             'top', 'right', 'bottom', 'left')
    for row, card in enumerate(cards):
        w, h = card['w'], card['h']
        middle_x, middle_y = (w - 8) // 2, (h - 8) // 2
        origins = ((0, 0), (w - 8, 0), (0, h - 8), (w - 8, h - 8),
                   (middle_x, 0), (w - 8, middle_y), (middle_x, h - 8), (0, middle_y))
        pieces = []
        for index, (x0, y0) in enumerate(origins):
            for y in range(8):
                for x in range(8):
                    canvas[(row * 8 + y) * 64 + index * 8 + x] = (
                        card['pixels'][(y0 + y) * w + x0 + x])
            identity = f'down/{card["action"]}/{index}'
            source_rect = [x0 + card['trim'][0], y0 + card['trim'][1], 8, 8]
            records.append({'id': identity, 'cell': [index, row], 'direction': 'down',
                            'action': card['action'], 'frame': index,
                            'anchor': [0, 0], 'hand_primary': None,
                            'slice_name': names[index], 'slice_source_rect': source_rect})
            pieces.append({'name': names[index], 'frame_id': 'coast_card_borders/' + identity,
                           'source_rect': source_rect})
        layouts.append({'rarity': card['action'], 'source_cell': source['cells'][row]['cell'],
                        'source_size': [w, h], 'corners': [8, 8], 'center': 'transparent',
                        'edge_mode': 'repeat native8px strips', 'pieces': pieces})
    stem = 'coast-card-border-slices-06a2d'
    png(ASSETS / (stem + '-native.png'), 64, 32, canvas)
    metadata = {'name': stem, 'grid': [64, 32], 'cell': [8, 8], 'format': 1,
                'palette_file': source['palette_file'], 'atlas_group': 'coast_ui',
                'cells': records}
    (ASSETS / (stem + '-sheet.json')).write_text(json.dumps(metadata, indent=2) + '\n')
    (ASSETS / 'coast-card-border-layout-06a2d.json').write_text(
        json.dumps({'source': source['name'], 'layouts': layouts}, indent=2) + '\n')
    path = ASSETS / 'production-06a2d.json'
    manifest = [item for item in json.loads(path.read_text())
                if item['actor'] != 'coast_card_borders']
    manifest.append({'actor': 'coast_card_borders', 'metadata': stem + '-sheet.json',
                     'actions': list(rarities), 'include_frames': True,
                     'normalize_source': False, 'cache': 'fixed', 'role': 'ui'})
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print('Four rarity borders:32 native8px pieces; original full frames retained')


if __name__ == '__main__':
    main()
