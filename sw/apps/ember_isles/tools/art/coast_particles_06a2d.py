#!/usr/bin/env python3
"""coast_particles_06a2d.py — art-plan6.1 literal native-pixel particle sprites.
Host-only; msg_aac2628fcd8c authorizes these2–16px hand drawings. No formula
constructs shapes. GPU model readback, exact2x and an8x additive review accompany them.
"""
import base64
import json

from coast_assets import ASSETS, ROOT
from compact_coast_frames import convert
from normalize_sample import decode_png, expand, png
from probe_coast_streaming import cells
from texture_sample import color_word

BUILD = ROOT / 'build/ember_isles/art_coast_particles'
OUTPUT = ROOT / 'outputs/ember_isles/art3-coast-assets/06a2d/particle-proof'
ELEMENTS = ('iron', 'ember', 'tide', 'star', 'shadow')


def rgba(word):
    return expand((word >> 11 & 31, word >> 5 & 63, word & 31, word >> 16 & 15))


def embedded(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = json.loads((ASSETS / 'coast-particle-pixels-06a2d.json').read_text())
    palette = json.loads((ASSETS / source['palette_file']).read_text())
    colors = {code: rgba(palette[index]) for code, index in source['codes'].items()}
    canvas = [(0, 0, 0, 0)] * (128 * 80)
    metadata_cells = []
    number = 0
    for particle in source['particles']:
        for frame, lines in enumerate(particle['frames']):
            column, row = number % 8, number // 8
            width, height = max(map(len, lines)), len(lines)
            x0, y0 = 8 - width // 2, 8 - height // 2
            for y, line in enumerate(lines):
                for x, code in enumerate(line):
                    canvas[(row * 16 + y0 + y) * 128 + column * 16 + x0 + x] = colors[code]
            metadata_cells.append({'id': f'down/{particle["id"]}/{frame}',
                'cell': [column, row], 'direction': 'down', 'action': particle['id'],
                'frame': frame, 'preferred_element': particle['element'],
                'anchor': [8, 8], 'hand_primary': None})
            number += 1
    stem = 'coast-particles-hand-06a2d'
    png(ASSETS / (stem + '-native.png'), 128, 80, canvas)
    variants = {element: f'coast-weapon-fx-{element}-06a2d-palette.json'
                for element in ELEMENTS[1:]}
    sheet = {'name': stem, 'grid': [128, 80], 'cell': [16, 16], 'format': 1,
             'palette_file': source['palette_file'], 'palette_variants': variants,
             'atlas_group': 'coast_particles', 'cells': metadata_cells}
    (ASSETS / (stem + '-sheet.json')).write_text(json.dumps(sheet, indent=2) + '\n')
    path = ASSETS / 'production-06a2d.json'
    manifest = json.loads(path.read_text())
    for item in manifest:
        if item['actor'] == 'coast_particles':
            item['include_frames'] = False
    entry = {'actor': 'coast_particles', 'metadata': stem + '-sheet.json',
        'actions': [p['id'] for p in source['particles']], 'include_frames': True,
        'normalize_source': False, 'cache': 'fixed', 'role': 'particle'}
    for index, item in enumerate(manifest):
        if item['metadata'] == entry['metadata']:
            manifest[index] = entry
            break
    else:
        manifest.append(entry)
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    frames = cells(sheet, [p['id'] for p in source['particles']], 'coast_particles')
    for frame, cell in zip(frames, metadata_cells):
        frame.update(role='particle', cache='fixed', palette_variants=variants,
                     preferred_element=cell['preferred_element'])
    records, ddr, texels = convert(frames, BUILD)
    lookup = {word: index for index, word in enumerate(palette)}
    lookup[0] = 0
    all_palettes = {'iron': palette} | {element: json.loads((ASSETS / p).read_text())
                                      for element, p in variants.items()}
    images, groups = {}, {}
    checked = 0
    for element, words in all_palettes.items():
        mapped = [rgba(words[lookup[color_word(p)]]) for p in canvas]
        atlas = OUTPUT / f'{element}-atlas.png'
        png(atlas, 128, 80, mapped)
        png(OUTPUT / f'{element}-atlas-8x.png', 1024, 640,
            [mapped[y // 8 * 128 + x // 8] for y in range(640) for x in range(1024)])
        images[element] = embedded(atlas)
    for index, (frame, record) in enumerate(zip(frames, records)):
        item = {'anchor': frame['anchor'], 'images': {}}
        for element, bank in record['palette_variants'].items():
            pixels = [rgba(all_palettes[element][lookup[color_word(p)]]) for p in frame['pixels']]
            width, height = frame['w'], frame['h']
            doubled = BUILD / f'{index:02d}-{element}-2x.png'
            png(doubled, width * 2, height * 2,
                [pixels[y // 2 * width + x // 2]
                 for y in range(height * 2) for x in range(width * 2)])
            dw, dh, raw = decode_png(doubled.read_bytes())
            for y in range(dh):
                for x in range(dw):
                    expected = bytes(pixels[y // 2 * width + x // 2])
                    if raw[(y * dw + x) * 4:(y * dw + x + 1) * 4] != expected:
                        raise ValueError(f'{frame["name"]}/{element}:2x mismatch{x},{y}')
                    checked += 1
            item['images'][element] = embedded(BUILD / 'gpu-readback' /
                                                f'{index:04d}-{bank}.png')
        groups.setdefault(frame['action'], []).append(item)
    result = {'frames': records, 'source_frames': len(frames), 'ddr_library_bytes': ddr,
              'gpu_readback_texels': texels, 'exact_2x_pixels': checked,
              'palette_groups': 5, 'source': 'literal hand-authored ASCII pixel drawings'}
    (BUILD / 'frames.json').write_text(json.dumps(result, indent=2) + '\n')
    page = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<title>06a-2d 原生粒子检视</title><style>body{background:#142033;color:#f4e4c8;
font:16px/1.6 system-ui;margin:24px}img,canvas{image-rendering:pixelated}
#atlas{width:1024px;height:640px}.grid{display:flex;flex-wrap:wrap;gap:16px}
article{background:#20344a;padding:12px}canvas{width:512px;height:192px}
select{font:inherit;padding:6px}</style><h1>原生粒子 · 8× 帧表和图层叠加检视</h1>'''
    page += (f'<p>9种 / {len(frames)}帧 / DDR {ddr} B /5元素色板；'
             f'GPU {texels}纹素回读和2× {checked}像素一致通过。</p>')
    page += '<p>字面像素手绘授权msg_aac2628fcd8c；生成试稿另存。固定位置叠加，参数推进由06b负责。</p>'
    page += '<select id="element">' + ''.join(f'<option>{e}</option>' for e in ELEMENTS)
    page += '</select><div style="overflow:auto"><img id="atlas"></div><div class="grid">'
    for kind, items in groups.items():
        page += f'<article><b>{kind} · {len(items)}帧</b><p>原帧 / 三层加色叠加</p>'
        page += f'<canvas width="64" height="24" data-kind="{kind}"></canvas></article>'
    page += '</div><script>const data=' + json.dumps({'images': images, 'groups': groups}) + ';'
    page += '''const loaded={};for(const [k,frames] of Object.entries(data.groups)){
loaded[k]=frames.map(f=>{const imgs={};for(const [e,url] of Object.entries(f.images)){
const i=new Image();i.src=url;imgs[e]=i}return{anchor:f.anchor,images:imgs}})}
let tick=0;const select=document.querySelector('#element');function draw(){
const e=select.value;document.querySelector('#atlas').src=data.images[e];
for(const c of document.querySelectorAll('canvas')){const frames=loaded[c.dataset.kind];
const f=frames[tick%frames.length],i=f.images[e],x=c.getContext('2d');
x.imageSmoothingEnabled=false;x.globalCompositeOperation='source-over';
x.fillStyle='#101c30';x.fillRect(0,0,64,24);if(i.complete){
x.drawImage(i,12-f.anchor[0],12-f.anchor[1]);x.globalCompositeOperation='lighter';
for(const [dx,dy] of [[0,0],[2,-1],[-2,1]])
x.drawImage(i,46+dx-f.anchor[0],12+dy-f.anchor[1])}}tick++}
setInterval(draw,140);draw();</script></html>'''
    (OUTPUT / 'index.html').write_text(page)
    print(f'PASS:{len(frames)} native frames,5 palettes,{texels} GPU texels,'
          f'{checked} exact2x pixels,DDR{ddr}B')


if __name__ == '__main__':
    main()
