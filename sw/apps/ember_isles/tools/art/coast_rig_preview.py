#!/usr/bin/env python3
"""coast_rig_preview.py — art-plan3 native Boss/guardian part inspection.
Host-only material composition, not gameplay or a GPU renderer. Every part keeps
its original pixels; only the explicitly symmetric right Boss fin is mirrored.
"""
import json

from coast_assets import ASSETS


def paint(canvas, width, frame, root, flip=False):
    w, h = frame['w'], frame['h']
    ax, ay = frame['anchor']
    if flip:
        ax = w - 1 - ax
    x0, y0 = root[0] - ax, root[1] - ay
    for y in range(h):
        for x in range(w):
            p = frame['pixels'][y * w + (w - 1 - x if flip else x)]
            if p[3]:
                canvas[(y0 + y) * width + x0 + x] = p


def cropped(canvas, width, height, root, actor, action, direction, number):
    occupied = [(x, y) for y in range(height) for x in range(width)
                if canvas[y * width + x][3]]
    x0, y0 = min(x for x, y in occupied), min(y for x, y in occupied)
    x1, y1 = max(x for x, y in occupied) + 1, max(y for x, y in occupied) + 1
    return {'actor': actor, 'action': action, 'direction': direction, 'frame': number,
            'w': x1 - x0, 'h': y1 - y0, 'anchor': [root[0] - x0, root[1] - y0],
            'pixels': [canvas[y * width + x] for y in range(y0, y1) for x in range(x0, x1)]}


def assemble(frames):
    rig = json.loads((ASSETS / 'coast-part-rigs-06a2d.json').read_text())
    indexed = {}
    for f in frames:
        indexed.setdefault((f['actor'], f['direction'], f['action']), []).append(f)
    for group in indexed.values():
        group.sort(key=lambda f: f['frame'])
    result = []
    guardian = rig['lighthouse_guardian']
    body_actor = guardian['body']
    if all((body_actor, d, 'idle') in indexed for d in guardian['directions']):
        for direction in guardian['directions']:
            for number, body in enumerate(indexed[body_actor, direction, 'idle']):
                width, height = guardian['canvas']
                root = guardian['root']
                canvas = [(0, 0, 0, 0)] * (width * height)
                origin = [root[i] - body['anchor'][i] for i in range(2)]
                for layer in guardian['layers']:
                    actor = layer['actor']
                    frame = body if actor == body_actor else indexed[actor, direction, 'idle'][0]
                    attachment = layer['attachment']
                    target = root if attachment == 'root' else [
                        origin[i] + body[attachment][i] for i in range(2)]
                    paint(canvas, width, frame, target)
                result.append(cropped(canvas, width, height, root, 'lighthouse_guardian',
                                      'idle', direction, number))
    boss = rig['tide_lord']
    if ('tide_lord_mouth', 'down', 'phase1_idle') in indexed:
        for phase in boss['phases']:
            for number in range(4):
                width, height = boss['canvas']
                root = boss['root']
                canvas = [(0, 0, 0, 0)] * (width * height)
                for layer in boss['layers']:
                    actor = layer['actor']
                    action = layer['action'].format(phase=phase)
                    if actor == 'tide_lord_fin' and phase == 3:
                        action = boss['phase3_fin_action']
                    group = indexed[actor, 'down', action]
                    frame = group[number % len(group)]
                    target = [root[i] + layer['offset'][i] for i in range(2)]
                    paint(canvas, width, frame, target, layer.get('flip_x', False))
                result.append(cropped(canvas, width, height, root, 'tide_lord',
                                      f'phase{phase}_idle', 'down', number))
    return result
