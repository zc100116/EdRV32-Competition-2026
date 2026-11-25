#!/usr/bin/env python3
"""tech5b measured compact block bound; scene cardinalities are assumptions.
Full fixed-region verdict belongs to06b with its actual UI/digit/glyph allocation.
"""
import itertools
import json

from coast_assets import ROOT

BUILD = ROOT / 'build/ember_isles/art_coast_production'


def main():
    packet = json.loads((BUILD / 'frames.json').read_text())
    frames = packet['frames']
    maxima = {}
    for f in frames:
        maxima[f['actor']] = max(maxima.get(f['actor'], 0), f['bytes'])
    # FPGA actions are walk/attack and two front death frames.
    enemies = ('tide_biter', 'salt_charger', 'drowned_watcher', 'reef_crab', 'mist_jellyfish')
    em = {a: max(f['bytes'] for f in frames if f['actor'] == a
                and (f['action'] in ('walk', 'attack')
                     or f['action'] == 'death' and f['direction'] == 'down' and f['frame'] < 2))
          for a in enemies}
    top = sorted((a for a in enemies if a != 'tide_biter'), key=em.get, reverse=True)[:2]
    top.append('tide_biter')
    aliases = {'lamp': ('lamp_off', 'lamp_ignite', 'lamp_lit'),
               'merchant': ('merchant', 'merchant_barter')}
    props = {}
    for p in ('barrel', 'crate', 'driftwood', 'coral', 'pillar', 'lamp', 'pole',
              'rock', 'grass', 'altar', 'merchant', 'rift'):
        actions = aliases.get(p, (p, p + '_break'))
        props[p] = max(f['bytes'] for f in frames
                       if f['role'] == 'prop' and f['action'] in actions)
    guardian = sum(maxima['lighthouse_guardian_' + p] for p in ('body', 'shield', 'weapon'))
    boss_parts = sum(maxima['tide_lord_' + p] for p in ('body', 'mouth', 'tail'))
    boss_parts += 2 * maxima['tide_lord_fin']
    branch_bytes = {b: sum(f['bytes'] for f in frames
                           if f.get('staff_projectile_branch') == b)
                    for b in ('base', 'evolution_a', 'evolution_b')}
    pinned_old = max(sum(v for b, v in branch_bytes.items() if b != current)
                     for current in branch_bytes)
    large_current_max = max(f['bytes'] for f in frames
                            if f['actor'] in ('coast_large_fx', 'coast_small_fx')
                            and f['cache'] == 'stream'
                            and 'cache_by_staff_branch' not in f)
    terms = {'keeper': maxima['keeper'], 'pet': 0, 'iron_guards': 0,
             'fire_seeds_three': 3 * maxima['fire_seed'],
             'terrain_30_kinds': 30 * 32 * 32, 'props_12_kinds': sum(props.values()),
             'large_effects_two': 2 * large_current_max,
             'old_staff_projectile_branches_pin_bound': pinned_old}
    common = sum(terms.values())
    ordinary = common + guardian + 12 * sum(em[a] for a in top)
    boss = common + boss_parts + 12 * em['tide_biter']
    fixed = [f for f in frames if f['cache'] == 'fixed' or 'cache_by_staff_branch' in f]
    forms = ('base', 'evolution_a', 'evolution_b')
    loadouts = []
    for sword, staff in itertools.product(forms, repeat=2):
        selected = {'sword/' + sword, 'staff/' + staff}
        material = [f for f in fixed if
                    f.get('cache_by_staff_branch', {}).get(staff, f['cache']) == 'fixed'
                    and ((f['actor'] == 'weapon_sword' and f['action'] == sword)
                    or (f['actor'] == 'weapon_staff' and f['action'] == staff)
                    or (not f['actor'].startswith('weapon_')
                        and f.get('fixed_loadout', 'common') in selected | {'common'}))]
        all_views = sum(f['bytes'] for f in material)
        weapon_views = [f for f in material if f['actor'].startswith('weapon_')]
        one_view = all_views - sum(f['bytes'] for f in weapon_views)
        one_view += sum(max(f['bytes'] for f in weapon_views if f['actor'] == actor)
                        for actor in ('weapon_sword', 'weapon_staff'))
        loadouts.append({'sword': sword, 'staff': staff,
                         'material_all_weapon_views_bytes': all_views,
                         'material_one_weapon_view_bytes': one_view})
    worst_one_view = max(x['material_one_weapon_view_bytes'] for x in loadouts)
    result = {'scope': 'measured source frame areas; assumed30 terrain/12 prop kinds',
              'measured_existing_frame_max_bytes': maxima, 'ordinary_enemy_max_bytes': em,
              'ordinary_top_three': top,
              'ordinary_selection': 'two medium kinds + tide-biter swarm',
              'common_terms_bytes': terms, 'guardian_parts_bytes': guardian,
              'staff_projectile_branch_payload_bytes': branch_bytes,
              'boss_parts_bytes': boss_parts, 'scene_prop_max_bytes': props,
              'ordinary_wave_estimate_bytes': ordinary, 'boss_wave_estimate_bytes': boss,
              'cache_budget_bytes': 144 * 1024,
              'fixed_all_source_payload_bytes': sum(f['bytes'] for f in fixed),
              'fixed_loadouts': loadouts,
              'fixed_material_worst_one_view_bytes': worst_one_view,
              'fixed_material_worst_all_views_bytes': max(x['material_all_weapon_views_bytes']
                                                         for x in loadouts),
              'fixed_other_reserved_estimate_bytes': 8 * 1024,
              'fixed_light_measured_bytes': sum(f['bytes'] for f in fixed
                                                if f['actor'] == 'coast_light'),
              'fixed_full_bytes': None,
              'fixed_verdict': '06b integrated measurement required; not passed',
              'fixed_with_other_reserved_estimate_bytes': worst_one_view + 8192,
              'fixed_initial_48k_estimated_gap_bytes': worst_one_view + 8192 - 48 * 1024,
              '06b_partition_reference': '06b selects final fixed/stream split',
              'ddr_full_bytes': packet['ddr_library_bytes'], 'palette_bytes': 16 * 1024}
    (BUILD / 'budget-estimate.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Ordinary {ordinary} B; Boss {boss} B; budget147456 B; DDR '
          f'{packet["ddr_library_bytes"]} B')
    print('Fixed measured material worst one view/all views: '
          f'{result["fixed_material_worst_one_view_bytes"]}/'
          f'{result["fixed_material_worst_all_views_bytes"]} B; other8KiB estimated')
    if max(ordinary, boss) > 144 * 1024:
        raise SystemExit(f'FAIL cache gap {max(ordinary, boss) - 144 * 1024} B')


if __name__ == '__main__':
    main()
