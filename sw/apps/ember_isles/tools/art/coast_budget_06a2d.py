#!/usr/bin/env python3
"""coast_budget_06a2d.py — tech 5b: ordinary/Boss wave bounds and labelled estimates.
Host-only: measured existing I8 block areas plus explicitly estimated unmade content.
Scene assumptions are coordinator-approved 32px tiles, 30 kinds and 12 props.
"""
import json

from coast_assets import ASSETS, ROOT
from compact_coast_frames import load_frames
from coast_production import fpga_frame
from probe_coast_streaming import cells

BUILD = ROOT / 'build/ember_isles/art_coast_production'


def measured_max(metadata, actor, actions):
    sheet = json.loads((ASSETS / metadata).read_text())
    frames = cells(sheet, actions, actor)
    return max(((f['w'] + 3) // 4 * 4) * ((f['h'] + 1) // 2 * 2) for f in frames)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    maxima = {}
    for f in load_frames():
        size = ((f['w'] + 3) // 4 * 4) * ((f['h'] + 1) // 2 * 2)
        maxima[f['actor']] = max(maxima.get(f['actor'], 0), size)
    maxima['tide_biter'] = measured_max('tide-biter-down-06a2d-sheet.json',
                                       'tide_biter', ('idle', 'walk'))
    for item in json.loads((ASSETS / 'production-06a2d.json').read_text()):
        if item['include_frames']:
            sheet = json.loads((ASSETS / item['metadata']).read_text())
            for frame in cells(sheet, item['actions'], item['actor']):
                frame['role'] = item['role']
                if fpga_frame(frame):
                    maximum = ((frame['w'] + 3) // 4 * 4) * ((frame['h'] + 1) // 2 * 2)
                    maxima[item['actor']] = max(maxima.get(item['actor'], 0), maximum)
    enemies = ('tide_biter', 'salt_charger', 'drowned_watcher',
               'reef_crab', 'mist_jellyfish')
    enemy_maxima = {k: maxima[k] for k in enemies}
    medium = [k for k in enemy_maxima if k != 'tide_biter']
    top_three = sorted(medium, key=enemy_maxima.get, reverse=True)[:2] + ['tide_biter']
    props = {'barrel': 1216, 'crate': 1872, 'driftwood': 1840, 'coral': 1680,
             'pillar': 2080, 'lamp': 1920, 'pole': 1120, 'rock': 768,
             'grass': 256, 'altar': 1536, 'merchant': 1408, 'rift': 2304}
    # Estimates use existing keeper/crab/prop silhouettes at the required body scale.
    guardian = maxima.get('lighthouse_guardian_body', 72 * 88)
    guardian += 28 * 52 + 24 * 64
    estimated = {'pet': 32 * 24, 'guardian': guardian,
                 'boss_body': 104 * 88, 'boss_head': 72 * 56,
                 'boss_tail': 104 * 48, 'boss_fin_left': 32 * 64,
                 'boss_fin_right': 32 * 64,
                 'terrain_30_kinds': 30 * 32 * 32,
                 'props_12_kinds': sum(props.values()),
                 'iron_guards_two': 2 * maxima['keeper'], 'fire_seeds_three': 3 * 16 * 16}
    common = (maxima['keeper'] + estimated['pet'] + estimated['terrain_30_kinds']
              + estimated['props_12_kinds'] + estimated['iron_guards_two']
              + estimated['fire_seeds_three'])
    ordinary = common + estimated['guardian'] + 12 * sum(enemy_maxima[k] for k in top_three)
    boss = common + sum(v for k, v in estimated.items() if k.startswith('boss_'))
    boss += 12 * enemy_maxima['tide_biter']
    result = {'scope': 'preproduction estimate, not a complete measured package',
              'measured_existing_frame_max_bytes': maxima,
              'unmade_frame_max_status': 'estimate: same silhouette/body scale as existing frames',
              'estimated_bytes': estimated,
              'estimate_basis': {'pet': 'crab aspect at 24px idle body',
                  'guardian': 'measured72px body + estimated28x52 shield +24x64 weapon',
                  'boss_parts': 'crab silhouette at 128px body, split parts with overlap',
                  'props': props,
                  'scene': 'coordinator msg_517f2b727c53: 30 32px tiles + 12 props'},
              'ordinary_top_three': top_three,
              'ordinary_selection': 'largest two medium kinds plus largest swarm kind',
              'ordinary_wave_estimate_bytes': ordinary,
              'boss_wave_estimate_bytes': boss, 'cache_budget_bytes': 144 * 1024,
              'fixed_full_bytes': None, 'ddr_full_bytes': None,
              'previous_partial_ddr_bytes': 229952,
              'previous_partial_ddr_commit': 'aea45e778'}
    (BUILD / 'budget-estimate.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Existing measured maxima {maxima}; top three {top_three}')
    print(f'ESTIMATE ordinary {ordinary} B; Boss {boss} B; budget 147456 B')
    print('Fixed region and full DDR library: not produced/not measured')
    if max(ordinary, boss) > 144 * 1024:
        raise SystemExit(f'FAIL estimated cache gap {max(ordinary, boss) - 144 * 1024} B')


if __name__ == '__main__':
    main()
