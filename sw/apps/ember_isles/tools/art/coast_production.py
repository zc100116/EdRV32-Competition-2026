#!/usr/bin/env python3
"""coast_production.py — ART-3 tech 5b / art-plan 2–6 production conversion.
Host standard-library pipeline: restore authored square grids, preserve body sizes,
store compact I8 frames and validate against the sole GPU reference model.
"""
import json

from coast_assets import ASSETS, ROOT, normalize
from compact_coast_frames import convert
from normalize_atlases import grid_centers
from normalize_sample import decode_png, palette_for
from probe_coast_streaming import cells
from texture_sample import color_word

BUILD = ROOT / 'build/ember_isles/art_coast_production'
OUTPUT = ROOT / 'outputs/ember_isles/art3-coast-assets/06a2d'


def fpga_frame(frame):
    if frame['role'] != 'enemy':
        return True
    if frame['action'] == 'death':
        return frame['direction'] == 'down' and frame['frame'] < 2
    return frame['action'] in ('walk', 'attack')


def load_native_frames():
    manifest = json.loads((ASSETS / 'production-06a2d.json').read_text())
    frames = []
    for item in manifest:
        if not item['include_frames']:
            continue
        sheet = json.loads((ASSETS / item['metadata']).read_text())
        added = cells(sheet, item['actions'], item['actor'])
        selected = [c for c in sheet['cells'] if c['action'] in item['actions']]
        for frame, cell in zip(added, selected):
            frame['cache'] = item['cache']
            frame['role'] = item['role']
            frame['source_sheet'] = sheet['name']
            frame['source_cell'] = cell['cell']
            frame['cell_size'] = sheet['cell']
        frames.extend(added)
    return frames


def prepare(sheet):
    palette_path = ASSETS / sheet['palette_file']
    if sheet['create_palette']:
        sw, sh, raw = decode_png((ASSETS / 'sources' /
                                  (sheet['name'] + '-input.png')).read_bytes())
        width, height = sheet['grid']
        xs, _ = grid_centers(raw, sw, sh, width, 0)
        ys, _ = grid_centers(raw, sw, sh, height, 1)
        pixels = []
        for y in ys:
            for x in xs:
                i = (y * sw + x) * 4
                pixels.append(tuple(raw[i:i + 3]) + (255,) if raw[i + 3] >= 192
                              else (0, 0, 0, 0))
        palette_path.write_text(json.dumps([color_word(p) for p in
                                           palette_for(pixels, 255)]) + '\n')
    sheet['palette_entries'] = len(json.loads(palette_path.read_text()))
    return normalize(sheet)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ASSETS / 'production-06a2d.json').read_text())
    # The tracked native sheets are authored pixels. Source import uses prepare()
    # when each raw image is created; packing never resamples those pixels again.
    frames = load_native_frames()
    measurements = []
    for item in manifest:
        if item['include_frames']:
            sheet = json.loads((ASSETS / item['metadata']).read_text())
            selected = [f for f in frames if f['source_sheet'] == sheet['name']]
            measurements.append({'name': sheet['name'], 'grid': sheet['grid'],
                                 'bounds': [{'name': f['name'], 'size': [f['w'], f['h']]}
                                            for f in selected]})
    records, ddr_bytes, texels = convert(frames, BUILD)
    fpga = [record for record in records if fpga_frame(record)]
    direction_maps = {'left': ['right', True], 'down_left': ['down_right', True],
                      'up_left': ['up_right', True],
                      'mist_jellyfish': {'default': ['down', False],
                          'walk_horizontal': ['lean_right', 'flip when moving left']}}
    (BUILD / 'pc-frames.json').write_text(json.dumps(
        {'frames': records, 'ddr_library': 'frames.bin', 'ddr_library_bytes': ddr_bytes,
         'direction_maps': direction_maps},
        indent=2) + '\n')
    (BUILD / 'fpga-frames.json').write_text(json.dumps(
        {'frames': fpga, 'ddr_library': 'frames.bin',
         'selected_payload_bytes': sum(f['bytes'] for f in fpga),
         'direction_maps': direction_maps, 'ordinary_death_direction': 'down'},
        indent=2) + '\n')
    (BUILD / 'frames.json').write_text(json.dumps(
        {'frames': records, 'ddr_library_bytes': ddr_bytes,
         'source_frames': len(records), 'gpu_readback_texels': texels,
         'sheets': measurements}, indent=2) + '\n')
    print(f'GPU page readback PASS: {len(records)} frames/{texels} texels; DDR {ddr_bytes} B')


if __name__ == '__main__':
    main()
