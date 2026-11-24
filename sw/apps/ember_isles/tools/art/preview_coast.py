#!/usr/bin/env python3
"""preview_coast.py — tech 5b/7, ART-3 asset inspection (not gameplay).
Host-only standard library. Exact integer display, APNG and embedded review page.
The source sheets and measured failures remain visible throughout production.
"""
import base64
import html
import json
import zlib

from normalize_sample import decode_png, png
from compose_sample import apng
from coast_assets import ASSETS, BUILD, OUTPUT


def walk_comparison(direction, current):
    images = []
    for name in ('keeper-' + direction + '-v2', current):
        width, height, raw = decode_png((ASSETS / (name + '-native.png')).read_bytes())
        images.append((width, raw))
    pixels = []
    for y in range(1024):
        width, raw = images[y // 512]
        sy = 64 + (y % 512) // 8
        for x in range(2048):
            i = (sy * width + x // 8) * 4
            p = tuple(raw[i:i + 4])
            pixels.append(p if p[3] else (232, 193, 129, 255))
    path = OUTPUT / (direction + '-walk-before-after-8x.png')
    png(path, 2048, 1024, pixels)
    return base64.b64encode(path.read_bytes()).decode()


def main():
    result = json.loads((BUILD / 'measurements.json').read_text())
    images = []
    cards = []
    for sheet in result['sheets'][:5]:
        name = sheet['name']
        path = ASSETS / (name + '-native.png')
        width, height, raw = decode_png(path.read_bytes())
        images.append((width, height, raw))
        encoded = base64.b64encode(path.read_bytes()).decode()
        heights = [b['size'][1] for b in sheet['bounds']]
        cards.append(f'<article><h2>{html.escape(name)}</h2>'
                     f'<p>Measured {min(heights)}–{max(heights)}px; standing target44px. '
                     'Four idle / four walk frames.</p>'
                     f'<img width="512" height="256" src="data:image/png;base64,{encoded}" '
                     f'alt="{html.escape(name)} normalized pixel sheet"></article>')
    frames = []
    for frame in range(4):
        output = [(12, 20, 32, 255)] * (640 * 360)
        for direction, (width, height, raw) in enumerate(images):
            for action in range(2):
                for y in range(64):
                    for x in range(64):
                        i = ((action * 64 + y) * width + frame * 64 + x) * 4
                        p = tuple(raw[i:i + 4])
                        if p[3]:
                            for dy in range(2):
                                for dx in range(2):
                                    ox = direction * 128 + x * 2 + dx
                                    oy = 20 + action * 170 + y * 2 + dy
                                    output[oy * 640 + ox] = p
        packed = b''.join(b'\0' + bytes(c for p in output[y * 640:(y + 1) * 640]
                                       for c in p) for y in range(360))
        frames.append(zlib.compress(packed, 9))
        png(OUTPUT / f'review-frame{frame:02d}.png', 640, 360, output)
        if frame == 0:
            png(OUTPUT / 'size-review.png', 640, 360, output)
            enlarged = [output[y // 2 * 640 + x // 2]
                        for y in range(720) for x in range(1280)]
            png(OUTPUT / 'size-review-2x.png', 1280, 720, enlarged)
    apng(OUTPUT / 'keeper-directions.apng', frames)
    comparison = [(12, 20, 32, 255)] * (640 * 360)
    for variant, suffix in enumerate(('-before-repair.png', '-native.png')):
        for direction, sheet in enumerate(result['sheets'][:5]):
            width, height, raw = decode_png((ASSETS / (sheet['name'] + suffix)).read_bytes())
            for y in range(64):
                for x in range(64):
                    i = (y * width + x) * 4
                    p = tuple(raw[i:i + 4])
                    if p[3]:
                        for dy in range(2):
                            for dx in range(2):
                                ox = direction * 128 + x * 2 + dx
                                oy = 20 + variant * 170 + y * 2 + dy
                                comparison[oy * 640 + ox] = p
    png(OUTPUT / 'repair-comparison.png', 640, 360, comparison)
    w, h, a = decode_png((OUTPUT / 'size-review.png').read_bytes())
    w2, h2, b = decode_png((OUTPUT / 'size-review-2x.png').read_bytes())
    for y in range(h2):
        for x in range(w2):
            ia, ib = (y // 2 * w + x // 2) * 4, (y * w2 + x) * 4
            if a[ia:ia + 4] != b[ib:ib + 4]:
                raise ValueError(f'2x preview differs at {x},{y}')
    animation = base64.b64encode((OUTPUT / 'keeper-directions.apng').read_bytes()).decode()
    compare = base64.b64encode((OUTPUT / 'repair-comparison.png').read_bytes()).decode()
    front_walk = walk_comparison('down', result['sheets'][0]['name'])
    back_walk = walk_comparison('up', result['sheets'][4]['name'])
    (OUTPUT / 'index.html').write_text(
        '<!doctype html><html lang="en"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width">'
        '<title>ART-3 coast materials in production</title>'
        '<style>body{background:#0c1420;color:#eee;font:17px system-ui;max-width:1100px;'
        'margin:40px auto;padding:20px}main{display:flex;gap:28px;flex-wrap:wrap}'
        'article{max-width:520px}img{image-rendering:pixelated;max-width:100%;height:auto}'
        'p{line-height:1.6}</style><h1>Coast material inspection</h1>'
        '<p>Work in progress. This is an asset preview, not a game screenshot or gameplay video. '
        'The complete coast pack is not accepted.</p>'
        '<p>Columns: down, down-right, right, up-right, up. '
        'Top row idle, bottom row walk. Display uses exact integer pixels.</p>'
        f'<img width="640" height="360" src="data:image/png;base64,{animation}" '
        'alt="Five direction idle and walk animation">'
        '<p>Authored repair comparison: top before, bottom after. Material-row repairs '
        'add one pixel where needed; pale rim edits color existing contour pixels.</p>'
        f'<img width="640" height="360" src="data:image/png;base64,{compare}" '
        'alt="Before and after pixel repair, five directions">'
        '<p>Front/back stride repair at exact8x: top prior walk, bottom corrected walk.</p>'
        f'<img width="1024" src="data:image/png;base64,{front_walk}" '
        'alt="Down walk before/after, exact8x pixels">'
        f'<img width="1024" src="data:image/png;base64,{back_walk}" '
        'alt="Up walk before/after, exact8x pixels">'
        '<main>' + ''.join(cards) + '</main></html>')
    print(f'PASS exact 2x {w}x{h} to {w2}x{h2}; embedded HTML, four-frame APNG')


if __name__ == '__main__':
    main()
