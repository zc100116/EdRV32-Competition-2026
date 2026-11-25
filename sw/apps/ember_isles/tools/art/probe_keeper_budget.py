#!/usr/bin/env python3
"""probe_keeper_budget.py — requested ART-3 I8/I4 keeper capacity comparison.
Host-only standard library. Exact frame/4x4-part deduplication, real GPU packing;
I4 is a separate proposal and never replaces the production I8 assets.
"""
import base64
import json

import coast_assets as coast
from normalize_sample import decode_png, expand, png

ASSETS = coast.ASSETS
BUILD = coast.ROOT / 'build/ember_isles/art_coast_probe'
OUTPUT = coast.OUTPUT
ACTIONS = ('idle', 'walk', 'dash', 'attack_staff', 'attack_codex', 'charge_staff',
           'hit', 'death', 'cast', 'interact')


def read_frames():
    config = json.loads((ASSETS / 'keeper-budget-sources.json').read_text())
    frames = []
    for item in config:
        sheet = json.loads((ASSETS / item['metadata']).read_text())
        w, h, raw = decode_png((ASSETS / (sheet['name'] + '-native.png')).read_bytes())
        for cell in sheet['cells']:
            if cell['action'] not in item['actions']:
                continue
            cx, cy = cell['cell']
            rgba = b''.join(raw[((cy * 64 + y) * w + cx * 64) * 4:
                               ((cy * 64 + y) * w + (cx + 1) * 64) * 4]
                            for y in range(64))
            frames.append({'id': cell['id'], 'action': cell['action'],
                           'direction': cell['direction'], 'rgba': rgba})
    return frames


def quantize(frames, words):
    palette = [expand((v >> 11 & 31, v >> 5 & 63, v & 31, v >> 16 & 15))
               for v in words]
    colors = {frame['rgba'][i:i + 4] for frame in frames
              for i in range(0, len(frame['rgba']), 4)}
    mapping = {bytes((0, 0, 0, 0)): bytes((0, 0, 0, 0))}
    for p in colors:
        if p[3]:
            mapping[p] = bytes(min(palette[1:], key=lambda c:
                                  sum((p[k] - c[k]) ** 2 for k in range(3))))
    return [{**frame, 'rgba': b''.join(mapping[frame['rgba'][i:i + 4]]
             for i in range(0, len(frame['rgba']), 4))} for frame in frames]


def measure(frames, fmt, palette_file, mode):
    coast.BUILD = BUILD / mode
    coast.BUILD.mkdir(parents=True, exist_ok=True)
    unique_frames, frame_sprites, frame_records = [], [], []
    tiles, tile_sprites, part_records = [], [], []
    distinct = {}
    for frame in frames:
        raw = frame['rgba']
        points = [(x, y) for y in range(64) for x in range(64)
                  if raw[(y * 64 + x) * 4 + 3]]
        x0, y0 = min(x for x, y in points), min(y for x, y in points)
        x1, y1 = max(x for x, y in points) + 1, max(y for x, y in points) + 1
        pixels = b''.join(raw[(y * 64 + x0) * 4:(y * 64 + x1) * 4]
                          for y in range(y0, y1))
        key = (x1 - x0, y1 - y0, pixels)
        if key not in unique_frames:
            unique_frames.append(key)
            frame_sprites.append({'name': f'frame/{len(unique_frames) - 1}',
                'w': x1 - x0, 'h': y1 - y0, 'trim': [0, 0],
                'pixels': [tuple(pixels[i:i + 4]) for i in range(0, len(pixels), 4)]})
        frame_records.append({'id': frame['id'], 'image': unique_frames.index(key),
                              'trim': [x0, y0]})
        action = frame['direction'] + '/' + frame['action']
        distinct.setdefault(action, [])
        if key not in distinct[action]:
            distinct[action].append(key)
        parts = []
        restored = bytearray(64 * 64 * 4)
        for y in range(0, 64, 4):
            for x in range(0, 64, 4):
                tile = b''.join(raw[((y + j) * 64 + x) * 4:
                                    ((y + j) * 64 + x + 4) * 4] for j in range(4))
                if not any(tile[i] for i in range(3, len(tile), 4)):
                    continue
                if tile not in tiles:
                    tiles.append(tile)
                    tile_sprites.append({'name': f'part/{len(tiles) - 1}',
                        'w': 4, 'h': 4, 'trim': [0, 0],
                        'pixels': [tuple(tile[i:i + 4]) for i in range(0, len(tile), 4)]})
                part_id = tiles.index(tile)
                parts.append([part_id, x, y])
                for j in range(4):
                    restored[((y + j) * 64 + x) * 4:((y + j) * 64 + x + 4) * 4] = (
                        tiles[part_id][j * 16:(j + 1) * 16])
        if bytes(restored) != raw:
            raise ValueError(frame['id'] + ': part reconstruction differs from native pixels')
        part_records.append({'id': frame['id'], 'parts': parts})
    full = coast.pack('frames', frame_sprites, fmt, palette_file)
    parts = coast.pack('parts4', tile_sprites, fmt, palette_file)
    counts = [len(frame['parts']) for frame in part_records]
    result = {'frames': len(frames), 'unique_frame_images': len(unique_frames),
              'unique_parts4': len(tiles), 'parts_per_frame': [min(counts), max(counts)],
              'average_parts_per_frame': sum(counts) / len(counts),
              'bbox_texture_bytes': full['texture_bytes'],
              'parts4_texture_bytes': parts['texture_bytes'], 'palette_groups': 1,
              'palette_entries': len(json.loads((ASSETS / palette_file).read_text())),
              'distinct_frames': {key: len(value) for key, value in distinct.items()},
              'frame_atlas': full, 'part_atlas': parts}
    (coast.BUILD / 'frames.json').write_text(json.dumps(frame_records, indent=2) + '\n')
    (coast.BUILD / 'parts4.json').write_text(json.dumps(part_records, indent=2) + '\n')
    return result


def comparison():
    words = json.loads((ASSETS / 'keeper-i4-proposal.json').read_text())
    cards = []
    manifest = json.loads((ASSETS / 'sheets.json').read_text())[:5]
    for sheet in manifest:
        w, h, raw = decode_png((ASSETS / (sheet['name'] + '-native.png')).read_bytes())
        original = {'rgba': raw}
        reduced = quantize([original], words)[0]['rgba']
        pixels = []
        for y in range(h * 16):
            data = raw if y < h * 8 else reduced
            sy = (y % (h * 8)) // 8
            for x in range(w * 8):
                i = (sy * w + x // 8) * 4
                p = tuple(data[i:i + 4])
                pixels.append(p if p[3] else (232, 193, 129, 255))
        path = OUTPUT / (sheet['name'] + '-i8-i4-8x.png')
        png(path, w * 8, h * 16, pixels)
        encoded = base64.b64encode(path.read_bytes()).decode()
        cards.append('<h2>' + sheet['name'] + '</h2><p>Top I8 / bottom I4, exact8x.</p>'
                     '<img width="1024" src="data:image/png;base64,' + encoded + '">')
    (OUTPUT / 'keeper-i4-comparison.html').write_text(
        '<!doctype html><meta charset="utf-8"><title>Keeper I8 / I4 proposal</title>'
        '<style>body{background:#0c1420;color:white;font:18px system-ui;max-width:1100px;'
        'margin:30px auto}img{image-rendering:pixelated;max-width:100%;height:auto}</style>'
        '<h1>Keeper16-color proposal</h1><p>Capacity/quality experiment; '
        'production remains I8. No frames or poses removed.</p>' + ''.join(cards))


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    frames = read_frames()
    seen = {frame['direction'] + '/' + frame['action'] for frame in frames}
    missing = [direction + '/' + action for direction in coast.DIRECTIONS
               for action in ACTIONS if direction + '/' + action not in seen]
    words = json.loads((ASSETS / 'keeper-i4-proposal.json').read_text())
    i8 = measure(frames, 1, 'keeper-palette.json', 'i8')
    reduced = quantize(frames, words)
    i4 = measure(reduced, 0, 'keeper-i4-proposal.json', 'i4')
    initial_frames = [frame for frame in frames if frame['action'] != 'charge_staff']
    initial_reduced = [frame for frame in reduced if frame['action'] != 'charge_staff']
    initial_i8 = measure(initial_frames, 1, 'keeper-palette.json', 'i8-initial')
    initial_i4 = measure(initial_reduced, 0, 'keeper-i4-proposal.json', 'i4-initial')
    size_issues = []
    for frame in frames:
        if frame['action'] not in ('cast', 'attack_staff', 'attack_codex', 'interact'):
            continue
        ys = [i // (64 * 4) for i in range(3, len(frame['rgba']), 4) if frame['rgba'][i]]
        height = max(ys) - min(ys) + 1
        if not 42 <= height <= 46:
            size_issues.append({'id': frame['id'], 'height': height})
    result = {'scope': 'only explicitly listed saved sources; missing coverage is not estimated',
              'expected_complete_frames': 200, 'measured_frames': len(frames),
              'variant': 'focused-core variant includes20 charge_staff frames',
              'missing_direction_actions': missing, 'I8': i8, 'I4': i4,
              'initial_without_evolution_charge': {'frames': len(initial_frames),
                  'I8': initial_i8, 'I4': initial_i4},
              'normal_pose_height_outside_42_46': size_issues,
              'half_limit_bytes': 98304}
    budget = json.loads((ASSETS / 'keeper-resident-budget.json').read_text())
    low = sum(item['actual_bytes'] if item['actual_bytes'] is not None
              else item['low_estimate'] for item in budget['other_items'])
    high = sum(item['actual_bytes'] if item['actual_bytes'] is not None
               else item['high_estimate'] for item in budget['other_items'])
    result['other_resident_budget'] = budget
    result['other_estimate_range'] = [low, high]
    for option in (i8, i4, initial_i8, initial_i4):
        option['forecast_with_other_estimates'] = [option['parts4_texture_bytes'] + low,
                                                  option['parts4_texture_bytes'] + high]
    (BUILD / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    comparison()
    for name, value in (('focused-I8', i8), ('focused-I4', i4),
                        ('initial-I8', initial_i8), ('initial-I4', initial_i4)):
        print(name, 'frames', value['frames'], 'unique', value['unique_frame_images'],
              'bbox', value['bbox_texture_bytes'], 'parts4', value['parts4_texture_bytes'],
              'unique_parts', value['unique_parts4'], 'quads/frame', value['parts_per_frame'])
    print('Missing direction/actions:', len(missing), missing)
    print('Other-resident estimates, not measured:', low, high)
    for name, option in (('I8', i8), ('I4', i4)):
        print(name, 'parts4 + other estimate range:',
              option['forecast_with_other_estimates'])
    exceeded = [name + ' keeper parts alone exceed96KiB by '
                + str(option['parts4_texture_bytes'] - 98304) + 'B'
                for name, option in (('I8', i8), ('I4', i4))
                if option['parts4_texture_bytes'] > 98304]
    if size_issues:
        exceeded.append(str(len(size_issues)) + ' normal poses exceed42–46px; see JSON')
    if exceeded:
        raise SystemExit('\n'.join(exceeded))


if __name__ == '__main__':
    main()
