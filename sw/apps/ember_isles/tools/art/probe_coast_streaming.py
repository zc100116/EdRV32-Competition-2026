#!/usr/bin/env python3
"""probe_coast_streaming.py — tech 5b: direct I8 frame-page capacity checkpoint.
Standard-library host tool, not a complete coast package or game integration.
Rebuild the new crab source, export existing keeper frames and measure the
coordinator's synchronized-enemy bound using actual legal GPU frame pages.
"""
import base64
import json
import struct

from coast_assets import ASSETS, ROOT, normalize
from normalize_sample import decode_png, png
from texture_sample import color_word
from tools.gpu.model.layout import interleave_texture, mip_layout
from tools.gpu.model.texture import Texture

BUILD = ROOT / 'build/ember_isles/art_coast_stream_probe'
OUTPUT = ROOT / 'outputs/ember_isles/art3-coast-assets/06a2'


def cells(sheet, actions, actor):
    width, height, raw = decode_png((ASSETS / (sheet['name'] + '-native.png')).read_bytes())
    cw, ch = sheet['cell']
    frames = []
    for cell in sheet['cells']:
        if cell['action'] not in actions:
            continue
        cx, cy = cell['cell']
        canvas = [tuple(raw[((cy * ch + y) * width + cx * cw + x) * 4:
                            ((cy * ch + y) * width + cx * cw + x) * 4 + 4])
                  for y in range(ch) for x in range(cw)]
        occupied = [(x, y) for y in range(ch) for x in range(cw) if canvas[y * cw + x][3]]
        x0 = min(x for x, y in occupied)
        y0 = min(y for x, y in occupied)
        x1 = max(x for x, y in occupied) + 1
        y1 = max(y for x, y in occupied) + 1
        pixels = [canvas[y * cw + x] for y in range(y0, y1) for x in range(x0, x1)]
        anchor = cell.get('feet', cell.get('anchor'))
        hand = cell.get('hand_primary')
        frames.append({'name': actor + '/' + cell['id'], 'actor': actor,
                       'action': cell['action'], 'direction': cell['direction'],
                       'frame': cell['frame'], 'w': x1 - x0, 'h': y1 - y0,
                       'trim': [x0, y0], 'anchor': [anchor[0] - x0, anchor[1] - y0],
                       'hand': None if hand is None else [hand[0] - x0, hand[1] - y0],
                       'pixels': pixels, 'palette_file': sheet['palette_file']})
        if 'hand_secondary' in cell:
            point = cell['hand_secondary']
            frames[-1]['hand_secondary'] = (None if point is None else
                                             [point[0] - x0, point[1] - y0])
    return frames


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    crab_sheet = json.loads((ASSETS / 'reef-crab-down-06a2-sheet.json').read_text())
    _, crab_measurement = normalize(crab_sheet)
    frames = []
    for item in json.loads((ASSETS / 'keeper-budget-sources.json').read_text()):
        sheet = json.loads((ASSETS / item['metadata']).read_text())
        frames.extend(cells(sheet, item['actions'], 'keeper'))
    frames.extend(cells(crab_sheet, ('idle', 'walk'), 'reef_crab'))
    palette_files = list(dict.fromkeys(frame['palette_file'] for frame in frames))
    palettes = [json.loads((ASSETS / path).read_text()) for path in palette_files]
    palettes = [palette + [0] * (256 - len(palette)) for palette in palettes]
    blob = bytearray()
    descriptors = []
    maxima = {}
    for frame in frames:
        width = max(8, 1 << (frame['w'] - 1).bit_length())
        height = max(8, 1 << (frame['h'] - 1).bit_length())
        bank = palette_files.index(frame['palette_file'])
        lookup = {word: index for index, word in enumerate(palettes[bank])}
        lookup[0] = 0
        texels = [0] * (width * height)
        for y in range(frame['h']):
            for x in range(frame['w']):
                texels[y * width + x] = lookup[color_word(frame['pixels'][y * frame['w'] + x])]
        packed = interleave_texture([texels], width, height, 1)
        offset = len(blob)
        assert offset % 32 == 0
        blob.extend(packed)
        descriptor = {'LOG2_W': width.bit_length() - 1, 'LOG2_H': height.bit_length() - 1,
                      'LEVELS': 1, 'FORMAT': 1, 'OFFSET': 0, 'PAL_GROUP': bank}
        texture = Texture(packed, palettes, descriptor)
        for y in range(height):
            for x in range(width):
                actual = texture.texel(x, y, 0, bank)
                expected = (frame['pixels'][y * frame['w'] + x]
                            if x < frame['w'] and y < frame['h'] else (0, 0, 0, 0))
                if actual != expected and not actual[3] == expected[3] == 0:
                    raise ValueError(f'{frame["name"]}: GPU texel mismatch at {x},{y}')
        maxima[frame['actor']] = max(maxima.get(frame['actor'], 0), len(packed))
        descriptors.append({key: value for key, value in frame.items()
                            if key not in ('pixels', 'palette_file')} |
                           {'offset': offset, 'bytes': len(packed), 'texture_w': width,
                            'texture_h': height, 'palette_group': bank, 'format': 'I8'})
    (BUILD / 'frames.bin').write_bytes(blob)
    (BUILD / 'palettes.bin').write_bytes(b''.join(struct.pack('<256I', *p) for p in palettes))
    result = {'scope': 'partial checkpoint, not full coast production',
              'fixed_bytes': None, 'scene_bytes': None, 'ddr_partial_bytes': len(blob),
              'source_frames': len(frames), 'per_actor_max_bytes': maxima,
              'partial_one_instance_each_bytes': sum(maxima.values()),
              'reef_crab_planned_actions': 5, 'drawn_directions_per_action': 5,
              'reef_crab_synchronized_lower_bound_bytes': 5 * 5 * maxima['reef_crab'],
              'cache_budget_bytes': 80 * 1024, 'new_crab': crab_measurement,
              'frames': descriptors}
    (BUILD / 'frames.json').write_text(json.dumps(result, indent=2) + '\n')
    source = ASSETS / 'reef-crab-down-06a2-native.png'
    width, height, raw = decode_png(source.read_bytes())
    pixels = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
    doubled = [pixels[(y // 2) * width + x // 2]
               for y in range(height * 2) for x in range(width * 2)]
    png(OUTPUT / 'reef-crab-2x.png', width * 2, height * 2, doubled)
    dw, dh, decoded = decode_png((OUTPUT / 'reef-crab-2x.png').read_bytes())
    for y in range(height * 2):
        for x in range(width * 2):
            assert decoded[(y * dw + x) * 4:(y * dw + x + 1) * 4] == bytes(
                pixels[(y // 2) * width + x // 2])
    encoded = base64.b64encode(source.read_bytes()).decode()
    (OUTPUT / 'index.html').write_text('<!doctype html><meta charset="utf-8">'
        '<title>06a-2 容量检查点：未完成整包</title>'
        '<style>body{background:#142033;color:#fff;font:18px sans-serif}'
        'img{image-rendering:pixelated;max-width:100%}</style>'
        '<h1>06a-2 礁壳蟹单帧纹理检查点</h1><p>素材检视；不是游戏截图或整包验收。</p>'
        f'<img width="{width * 4}" height="{height * 4}" '
        f'src="data:image/png;base64,{encoded}" alt="八帧礁壳蟹">'
        '<p>直接独立帧纹理：每帧64×64 I8=4096 B；同步保守上界仅蟹一种即102400 B，'
        '超过80 KiB。固定区、场景区和完整动画帧库尚未生产。</p>')
    print(f'GPU model texel readback and exact 2x PASS; {len(frames)} partial source frames')
    print(f'partial DDR {len(blob)} B; per-instance partial bound {sum(maxima.values())} B')
    print(f'FAIL: reef-crab synchronized lower bound {5 * 5 * maxima["reef_crab"]} B '
          f'> {80 * 1024} B cache; fixed/scene/full DDR unmeasured')
    raise SystemExit(1)


if __name__ == '__main__':
    main()
