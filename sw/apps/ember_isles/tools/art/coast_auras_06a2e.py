#!/usr/bin/env python3
"""06a-2e / art-plan 1,3: import eight authored elite aura loops.
Host standard library; restore the declared pixel grid, reuse production palettes.
No aura geometry or intermediate animation frame is synthesized here.
"""
import json

from coast_assets import ASSETS
from normalize_atlases import grid_centers
from normalize_sample import decode_png, expand, png

# Existing production palette groups, shared with weapon effects and particles.
DESIGNS = {
    'haste': ('tide', 'feet', 220),
    'ward': ('tide', 'body', 180),
    'split': ('ember', 'body', 240),
    'reflect': ('iron', 'outer', 210),
    'dim': ('shadow', 'body', 145),
    'fanatic': ('ember', 'body', 190),
    'elemental': ('iron', 'outer', 170),
    'teleport': ('star', 'feet', 210),
}


def main():
    path = ASSETS / 'production-06a2d.json'
    manifest = json.loads(path.read_text())
    for affix, (element, region, alpha) in DESIGNS.items():
        stem = 'coast-elite-aura-' + affix + '-06a2e'
        sw, sh, raw = decode_png((ASSETS / 'sources' / (stem + '-input.png')).read_bytes())
        xs, _ = grid_centers(raw, sw, sh, 240, 0)
        ys, _ = grid_centers(raw, sw, sh, 160, 1)
        palette_file = f'coast-weapon-fx-{element}-06a2d-palette.json'
        if affix == 'fanatic':
            palette_file = 'keeper-palette.json'
        words = json.loads((ASSETS / palette_file).read_text())[:16]
        palette = [expand((w >> 11 & 31, w >> 5 & 63, w & 31, w >> 16 & 15))
                   for w in words]
        if affix == 'fanatic':
            # Reuse the keeper's crimson scarf ramp, rather than the orange ember ramp.
            palette = [(0, 0, 0, 0)] + [c for c in palette[1:]
                       if c[0] > 2 * c[1] and c[0] * 2 > 3 * c[2]]
        source = [tuple(raw[(y * sw + x) * 4:(y * sw + x + 1) * 4])
                  for y in ys for x in xs]
        # Same production alpha cutoff as 06a-2d; opacity is a GPU global alpha.
        mapping = {p: (min((c for c in palette[1:] if c[3] == 255),
                           key=lambda c: sum((p[k] - c[k]) ** 2 for k in range(3)))
                       if p[3] >= 192 else (0, 0, 0, 0)) for p in set(source)}
        pixels = [mapping[p] for p in source]
        png(ASSETS / (stem + '-native.png'), 240, 160, pixels)
        action = 'elite_aura_' + affix
        sheet = {'name': stem, 'grid': [240, 160], 'cell': [80, 80],
                 'format': 0, 'texture_format': 0, 'palette_file': palette_file,
                 'atlas_group': 'coast_small_fx',
                 'resource': 'coast_small_fx/' + action,
                 'animation_ticks': 6, 'animation_loop': True, 'direction_independent': True,
                 'global_alpha': alpha, 'aura_region': region, 'blend': 'alpha',
                 'filter': 'nearest', 'cells': [
                     {'id': f'down/{action}/{f}', 'cell': [f % 3, f // 3],
                      'direction': 'down', 'action': action, 'frame': f,
                      'anchor': [40, 64], 'hand_primary': None} for f in range(6)]}
        if affix == 'elemental':
            sheet['palette_variants'] = {
                e: f'coast-weapon-fx-{e}-06a2d-palette.json'
                for e in ('ember', 'tide', 'shadow')}
        (ASSETS / (stem + '-sheet.json')).write_text(json.dumps(sheet, indent=2) + '\n')
        metadata = stem + '-sheet.json'
        manifest = [item for item in manifest if item['metadata'] != metadata]
        manifest.append({'actor': 'coast_small_fx', 'metadata': metadata,
                         'actions': [action], 'include_frames': True,
                         'normalize_source': False, 'cache': 'stream', 'role': 'elite_aura'})
    for icon in ('xp', 'gold', 'ember', 'health', 'oil'):
        stem = 'coast-pickup-' + icon + '-06a2e'
        sw, sh, raw = decode_png((ASSETS / 'sources' / (stem + '-input.png')).read_bytes())
        xs, _ = grid_centers(raw, sw, sh, 24, 0)
        ys, _ = grid_centers(raw, sw, sh, 24, 1)
        palette_file = 'coast-ui-06a2d-palette.json'
        if icon == 'health':
            palette_file = 'keeper-palette.json'
        words = json.loads((ASSETS / palette_file).read_text())
        palette = [expand((w >> 11 & 31, w >> 5 & 63, w & 31, w >> 16 & 15))
                   for w in words]
        pixels = []
        for y in ys:
            for x in xs:
                p = tuple(raw[(y * sw + x) * 4:(y * sw + x + 1) * 4])
                choices = palette[1:]
                if icon == 'health' and p[0] > 100:
                    choices = [c for c in choices
                               if c[0] > 2 * c[1] and c[0] * 2 > 3 * c[2]]
                pixels.append(min(choices, key=lambda c: sum(
                    (p[k] - c[k]) ** 2 for k in range(3))) if p[3] >= 192
                    else (0, 0, 0, 0))
        png(ASSETS / (stem + '-native.png'), 24, 24, pixels)
        sheet = {'name': stem, 'grid': [24, 24], 'cell': [24, 24], 'format': 1,
                 'palette_file': palette_file, 'atlas_group': 'coast_ui_icons',
                 'resource': 'coast_ui_icons/' + icon, 'cells': [
                     {'id': f'down/{icon}/0', 'cell': [0, 0], 'direction': 'down',
                      'action': icon, 'frame': 0, 'anchor': [12, 12], 'hand_primary': None}]}
        metadata = stem + '-sheet.json'
        (ASSETS / metadata).write_text(json.dumps(sheet, indent=2) + '\n')
        manifest = [item for item in manifest if item['metadata'] != metadata]
        manifest.append({'actor': 'coast_ui_icons', 'metadata': metadata,
                         'actions': [icon], 'include_frames': True,
                         'normalize_source': False, 'cache': 'fixed', 'role': 'ui_icon'})
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print('Imported 8 aura sheets / 48 frames and 5 pickup icons; existing palettes reused')


if __name__ == '__main__':
    main()
