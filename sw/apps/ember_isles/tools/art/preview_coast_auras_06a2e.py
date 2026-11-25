#!/usr/bin/env python3
"""06a-2e acceptance: GPU texels, exact 2x, fixed-size loops and all 28 pairs.
Host standard library. Inspection uses actual production GPU readbacks; bodies
alone are displayed at 1.25x, and no aura frame is resized for a smaller enemy.
"""
import base64
import itertools
import json
from functools import lru_cache
import subprocess

from coast_assets import ROOT
import coast_budget_06a2d as budget
import coast_production as production
from coast_production import load_native_frames
from normalize_sample import decode_png, expand, png
from texture_sample import color_word

OUTPUT = ROOT / 'outputs/ember_isles/art3-coast-assets/06a2e'
BUILD = ROOT / 'build/ember_isles/art_coast_auras_06a2e'
IDS = ('haste', 'ward', 'split', 'reflect', 'dim', 'fanatic', 'elemental', 'teleport')
BASELINE = '8a0eff2f1'


@lru_cache(None)
def baseline_file(name):
    return subprocess.check_output(['git', 'show', BASELINE +
                                   ':sw/apps/ember_isles/assets/art_coast/' + name], cwd=ROOT)


def compare_baseline(records, excluded_actions):
    """Compare unmodified native/variant RGBA frames directly with the git baseline."""
    current = {r['name']: (i, r) for i, r in enumerate(records)}
    frames, cases, pixels, mismatches = 0, 0, 0, 0
    manifest = json.loads(baseline_file('production-06a2d.json'))
    for item in manifest:
        if not item['include_frames']:
            continue
        sheet = json.loads(baseline_file(item['metadata']))
        width, _, raw = decode_png(baseline_file(sheet['name'] + '-native.png'))
        palette = json.loads(baseline_file(sheet['palette_file']))
        palette += [0] * (256 - len(palette))
        lookup = {word: i for i, word in enumerate(palette)}
        lookup[0] = 0
        variants = {'native': palette} | {
            k: json.loads(baseline_file(v)) for k, v in sheet.get('palette_variants', {}).items()}
        cw, ch = sheet['cell']
        for cell in sheet['cells']:
            if cell['action'] not in item['actions'] or cell['action'] in excluded_actions:
                continue
            cx, cy = cell['cell']
            canvas = [tuple(raw[((cy * ch + y) * width + cx * cw + x) * 4:
                                ((cy * ch + y) * width + cx * cw + x + 1) * 4])
                      for y in range(ch) for x in range(cw)]
            occupied = [(x, y) for y in range(ch) for x in range(cw) if canvas[y * cw + x][3]]
            x0, y0 = min(x for x, y in occupied), min(y for x, y in occupied)
            x1, y1 = max(x for x, y in occupied) + 1, max(y for x, y in occupied) + 1
            source = [canvas[y * cw + x] for y in range(y0, y1) for x in range(x0, x1)]
            name = item['actor'] + '/' + cell['id']
            index, record = current[name]
            frame_failed = False
            for element, words in variants.items():
                bank = (record['native_palette_group'] if element == 'native'
                        else record['palette_variants'][element])
                w, h, actual = decode_png((BUILD / 'gpu-readback' /
                                         f'{index:04d}-{bank}.png').read_bytes())
                expected = source if element == 'native' else [expand((
                    words[lookup[color_word(p)]] >> 11 & 31,
                    words[lookup[color_word(p)]] >> 5 & 63,
                    words[lookup[color_word(p)]] & 31,
                    words[lookup[color_word(p)]] >> 16 & 15)) for p in source]
                expected = bytes(v for p in expected for v in p)
                frame_failed |= (w != x1 - x0 or h != y1 - y0 or actual != expected)
                cases += 1
                pixels += w * h
            frames += 1
            mismatches += int(frame_failed)
    result = {'commit': BASELINE, 'frames': frames, 'palette_cases': cases,
              'rgba_pixels': pixels, 'mismatching_frames': mismatches}
    if mismatches:
        raise ValueError(f'Existing-frame RGBA differs from {BASELINE}: {result}')
    return result


def embed(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def main(excluded_actions=()):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    packet = json.loads((BUILD / 'frames.json').read_text())
    records = packet['frames']
    baseline = compare_baseline(records, excluded_actions)
    native = load_native_frames()
    fpga = json.loads((BUILD / 'fpga-frames.json').read_text())['frames']
    palette_bytes = (BUILD / 'palettes.bin').read_bytes()
    data, maxima, areas, colors, icons = {}, {}, {}, {}, {}
    checked = 0
    gpu_texels = 0
    for index, (record, source) in enumerate(zip(records, native)):
        if (record['role'] != 'elite_aura'
                and record.get('resource', '').split('/')[0] != 'coast_ui_icons'):
            continue
        action = record['action']
        key = action.removeprefix('elite_aura_')
        banks = {'iron': record['native_palette_group']} | record['palette_variants']
        images = {}
        for element, bank in banks.items():
            path = BUILD / 'gpu-readback' / f'{index:04d}-{bank}.png'
            w, h, raw = decode_png(path.read_bytes())
            pixels = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
            # Exact 2x proof includes each elemental palette's real GPU output.
            target = OUTPUT / f'{action}-{record["frame"]}-{element}-2x.png'
            png(target, w * 2, h * 2,
                [pixels[y // 2 * w + x // 2] for y in range(h * 2) for x in range(w * 2)])
            dw, dh, doubled = decode_png(target.read_bytes())
            for y in range(dh):
                for x in range(dw):
                    actual = doubled[(y * dw + x) * 4:(y * dw + x + 1) * 4]
                    expected = bytes(pixels[y // 2 * w + x // 2])
                    if actual != expected:
                        raise ValueError(f'{action}/{element}: 2x mismatch {x},{y}')
                    checked += 1
            if bank == record['native_palette_group'] and pixels != source['pixels']:
                raise ValueError(f'{action}: GPU/source pixels differ')
            images[element] = embed(path)
            gpu_texels += 128 * 128
        item = {'images': images, 'anchor': record['anchor'], 'w': record['w'],
                'h': record['h'], 'alpha': record.get('global_alpha', 255),
                'region': record.get('aura_region'), 'ticks': record.get('animation_ticks', 6)}
        if record['role'] == 'elite_aura':
            if record['format'] != 'I4':
                raise ValueError(f'{action}: expected I4 production frame')
            data.setdefault(key, []).append(item)
            maxima[key] = max(maxima.get(key, 0), record['bytes'])
            bw, bh = record['block_aligned_size']
            areas[key] = max(areas.get(key, 0), bw * bh)
            colors.setdefault(key, {0}).update(color_word(p) for p in source['pixels'])
        else:
            icons[key] = item
    for key, frames in data.items():
        if len(frames) != 6 or len({json.dumps(f['images']) for f in frames}) != 6:
            raise ValueError(f'{key}: expected six distinct authored frames')
        if sum(r['action'] == 'elite_aura_' + key and r['format'] == 'I4' for r in fpga) != 6:
            raise ValueError(f'{key}: FPGA subset lost frames')
    bodies = {}
    for actor in ('reef_crab', 'tide_biter'):
        index = next(i for i, r in enumerate(records) if r['actor'] == actor
                     and r['action'] == 'idle' and r['direction'] == 'down' and r['frame'] == 0)
        r = records[index]
        bodies[actor] = {'image': embed(BUILD / 'gpu-readback' /
                                      f'{index:04d}-{r["native_palette_group"]}.png'),
                         'w': r['w'], 'h': r['h'], 'anchor': r['anchor']}
    terrains = []
    for actor in ('terrain_sand', 'terrain_shallow', 'terrain_reef',
                  'terrain_ruins', 'terrain_grass'):
        matches = [(i, r) for i, r in enumerate(records) if r['actor'] == actor]
        if matches:
            i, r = matches[0]
            terrains.append(embed(BUILD / 'gpu-readback' /
                                  f'{i:04d}-{r["native_palette_group"]}.png'))
    # The original scene assumptions remain those recorded by 06a-2d.
    original_budget = json.loads((BUILD / 'budget-estimate.json').read_text())
    worst = sorted(maxima, key=maxima.get, reverse=True)[:2]
    ordinary = original_budget['ordinary_wave_estimate_bytes']
    total = ordinary + sum(maxima[k] for k in worst)
    result = {'auras': maxima, 'aura_max_block_texels': areas,
              'aura_color_counts': {key: len(v) for key, v in colors.items()},
              'baseline_comparison': baseline, 'worst_two_distinct': worst,
              'ordinary_original_bytes': ordinary, 'ordinary_plus_two_distinct_bytes': total,
              'ordinary_plus_two_maximum_bytes': ordinary + 2 * max(maxima.values()),
              'stream_budget_bytes': 147456, 'margin_bytes': 147456 - total,
              'source_frames': sum(len(v) for v in data.values()),
              'fpga_aura_frames': sum(r['role'] == 'elite_aura' for r in fpga),
              'gpu_readback_texels_auras_and_icons': gpu_texels,
              'exact_2x_pixels': checked, 'palette_groups_full_pack': len(palette_bytes) // 1024,
              'ddr_library_bytes_full_pack': packet['ddr_library_bytes'],
              'full_pack_gpu_readback_texels': packet['gpu_readback_texels'],
              'pickup_fixed_bytes': sum(r['bytes'] for r in records
                                        if r.get('resource', '') in
                                        ['coast_ui_icons/' + k for k in icons])}
    (OUTPUT / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    page = '''<!doctype html><html lang="zh"><meta charset="utf-8"><title>06a-2e 精英词缀</title>
<style>body{margin:24px;background:#152331;color:#f4e8d2;font:15px/1.5 system-ui}
h1{color:#81e1d6}section{display:flex;flex-wrap:wrap;gap:16px}article{padding:12px;
background:#21384a;border:1px solid #416378;border-radius:8px}canvas,img{image-rendering:pixelated}
canvas{width:480px;height:192px}button,select{font:inherit;padding:5px}small{color:#b8ccd9}
</style><h1>精英词缀 · 06a-2e</h1><p>同一动画时钟 / 每帧6 ticks / 六帧循环。
光环1:1，礁壳蟹与潮啮身体1.25×；图像来自GPU模型逐纹素回读，非游戏录像。</p>
<button id="pause">暂停</button> <label>元素护盾 <select id="element">'''
    page += ''.join(f'<option>{e}</option>' for e in ('iron', 'ember', 'tide', 'shadow'))
    page += '</select></label><h2>8种单词缀：原光环 / 礁壳蟹 / 潮啮</h2><section>'
    for key in IDS:
        page += (f'<article><b>coast_small_fx/elite_aura_{key}</b><br>'
                 f'<small>6帧I4 · 最大块面积{areas[key]}纹素 / {maxima[key]} B</small>'
                 f'<br><canvas width="240" height="96" data-pair="{key}" '
                 'data-solo="1"></canvas></article>')
    page += '</section><h2>全部28对双词缀 · 礁壳蟹 / 潮啮</h2><section>'
    for a, b in itertools.combinations(IDS, 2):
        page += (f'<article><b>{a} + {b}</b><br><canvas width="240" height="96" '
                 f'data-pair="{a},{b}"></canvas></article>')
    page += '</section><h2>5种掉落图标 · 沙滩 / 浅水 / 礁石 / 废墟 / 草地</h2>'
    page += '<p>ember为燃烧煤块，oil为油滴；与遗物袋和油壶不同。</p><section>'
    for key in icons:
        page += (f'<article><b>coast_ui_icons/{key}</b><br><canvas width="240" height="96" '
                 f'data-icon="{key}"></canvas></article>')
    page += '</section><h2>测量</h2><pre>' + json.dumps(result, indent=2) + '</pre>'
    page += '<script>const data=' + json.dumps({'auras': data, 'bodies': bodies,
                                              'icons': icons, 'terrains': terrains}) + ';'
    page += '''const assets=[];function img(url){const i=new Image();i.src=url;
assets.push(i);return i}
for(const fs of Object.values(data.auras))for(const f of fs)
for(const k in f.images)f.images[k]=img(f.images[k]);
for(const b of Object.values(data.bodies))b.image=img(b.image);
for(const f of Object.values(data.icons))for(const k in f.images)f.images[k]=img(f.images[k]);
data.terrains=data.terrains.map(img);let paused=false,clock=0,last=performance.now();
document.querySelector('#pause').onclick=()=>{paused=!paused};
function aura(x,key,cx,foot,tick){const fs=data.auras[key];
const f=fs[Math.floor(tick/fs[0].ticks)%fs.length];
const e=key==='elemental'?document.querySelector('#element').value:'iron';
x.globalAlpha=f.alpha/255;x.drawImage(f.images[e],cx-f.anchor[0],foot-f.anchor[1]);x.globalAlpha=1}
function body(x,key,cx,foot){const b=data.bodies[key];x.drawImage(b.image,
cx-b.anchor[0]*1.25,foot-b.anchor[1]*1.25,b.w*1.25,b.h*1.25)}
function draw(now){if(!paused)clock+=(now-last)*60/1000;last=now;
for(const c of document.querySelectorAll('canvas')){const x=c.getContext('2d');
x.imageSmoothingEnabled=false;x.globalAlpha=1;x.fillStyle='#142333';x.fillRect(0,0,240,96);
if(c.dataset.icon){const f=data.icons[c.dataset.icon];for(let i=0;i<5;i++){
const t=data.terrains[i];if(t&&t.complete)x.drawImage(t,i*48,28,48,48);
x.drawImage(f.images.iron,i*48+24-f.anchor[0],52-f.anchor[1]);}continue}
const keys=c.dataset.pair.split(','),solo=c.dataset.solo;
const places=solo?[[40,null],[120,'reef_crab'],[200,'tide_biter']]:
[[60,'reef_crab'],[180,'tide_biter']];
for(const [cx,b] of places){for(const k of keys)
if(data.auras[k][0].region==='feet')aura(x,k,cx,77,clock);
if(b)body(x,b,cx,77);
for(const k of keys)if(data.auras[k][0].region!=='feet')aura(x,k,cx,77,clock)}}
requestAnimationFrame(draw)}
Promise.all(assets.map(i=>i.decode())).then(()=>requestAnimationFrame(draw));
</script></html>'''
    (OUTPUT / 'index.html').write_text(page)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    # Keep this acceptance run separate from the concurrently integrated V1 pack.
    production.BUILD = BUILD
    production.main()
    budget.BUILD = BUILD
    budget.main()
    main()
