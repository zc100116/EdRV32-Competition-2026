#!/usr/bin/env python3
"""ART-3 self-contained material inspection, exact2x and30s material preview.
Every comparison uses the actual GPU-model readback; this never executes gameplay.
"""
import base64
from collections import defaultdict
import json
from pathlib import Path
import subprocess
import sys

from coast_assets import ASSETS, ROOT
from coast_production import BUILD, OUTPUT, load_native_frames
from coast_rig_preview import assemble
from normalize_sample import decode_png, expand, png
from texture_sample import color_word

sys.path.insert(0, str(ROOT / 'sw/apps/ember_isles/tools'))
from font_convert import read_glyphs

DIRECTIONS = ('down', 'down_right', 'right', 'up_right', 'up')


def embed(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def rgba(word):
    return expand((word >> 11 & 31, word >> 5 & 63, word & 31, word >> 16 & 15))


def draw(canvas, width, frame, x0, y0, scale=1):
    for y in range(frame['h']):
        for x in range(frame['w']):
            p = frame['pixels'][y * frame['w'] + x]
            if p[3]:
                for dy in range(scale):
                    for dx in range(scale):
                        canvas[(y0 + y * scale + dy) * width + x0 + x * scale + dx] = p


def caption(canvas, width, text, x0, y0, glyphs):
    for char in text:
        advance, rows = glyphs[ord(char)]
        for y, row in enumerate(rows):
            for x in range(12):
                if row & (1 << (11 - x)):
                    canvas[(y0 + y) * width + x0 + x] = (119, 221, 215, 255)
        x0 += advance


def video(frames, rigs):
    groups = defaultdict(list)
    for f in frames + rigs:
        groups[f['actor'], f['action'], f['direction']].append(f)
    for group in groups.values():
        group.sort(key=lambda f: f['frame'])
    def clips(actors):
        return [g for (a, action, d), g in groups.items() if a in actors
                and d == 'down' and not action.startswith('phase2')]
    sections = [clips(('keeper',)),
                [groups[a, 'walk', 'down'] for a in
                 ('tide_biter', 'salt_charger', 'drowned_watcher', 'reef_crab', 'mist_jellyfish')]
                + [groups[a, 'attack', 'down'] for a in
                   ('salt_charger', 'reef_crab', 'mist_jellyfish')],
                [groups['lighthouse_guardian', 'idle', d] for d in DIRECTIONS]
                + [groups['tide_lord', f'phase{p}_idle', 'down'] for p in (1, 2, 3)],
                clips(('coast_large_fx', 'fire_seed')),
                clips(('weapon_sword', 'weapon_staff', 'coast_small_fx')),
                clips(('coast_particles',))]
    labels = [g[0]['actor'] + ' ' + g[0]['action'] for section in sections for g in section]
    title = '06a-2d 素材预览 · 非游戏录像'
    glyphs = read_glyphs(set(map(ord, title + ''.join(labels))))
    width, height = 960, 540
    target = OUTPUT / 'assets-preview-30s.mp4'
    encoder = subprocess.Popen([str(Path.home() / '.local/opt/video/bin/ffmpeg'),
        '-v', 'error', '-y', '-f', 'rawvideo', '-pixel_format', 'rgb24',
        '-video_size', '960x540', '-framerate', '8', '-i', 'pipe:0', '-t', '30',
        '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(target)], stdin=subprocess.PIPE)
    for tick in range(240):
        canvas = [(25, 38, 56, 255)] * (width * height)
        caption(canvas, width, title, 16, 12, glyphs)
        section = sections[tick // 40]
        for panel in range(8):
            group = section[(panel + (tick // 4 if len(section) > 8 else 0)) % len(section)]
            f = group[tick % len(group)]
            label = f['actor'] + ' ' + f['action']
            caption(canvas, width, label[:29], 16 + panel % 4 * 236,
                    40 + panel // 4 * 244, glyphs)
            scale = max(1, min(4, 196 // max(f['w'], f['h'])))
            x = 16 + panel % 4 * 236 + (220 - f['w'] * scale) // 2
            y = 62 + panel // 4 * 244 + 196 - f['h'] * scale
            draw(canvas, width, f, x, y, scale)
        encoder.stdin.write(b''.join(bytes(p[:3]) for p in canvas))
    encoder.stdin.close()
    if encoder.wait() != 0:
        raise RuntimeError('Material-preview ffmpeg encoding failed')
    return target


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    proof = BUILD / 'frames-2x'
    proof.mkdir(parents=True, exist_ok=True)
    packet = json.loads((BUILD / 'frames.json').read_text())
    budget = json.loads((BUILD / 'budget-estimate.json').read_text())
    frames = load_native_frames()
    data, groups, checked = [], defaultdict(list), 0
    display_frames = []
    for index, (f, record) in enumerate(zip(frames, packet['frames'])):
        source = json.loads((ASSETS / f['palette_file']).read_text())
        lookup = {word: i for i, word in enumerate(source)}
        lookup[0] = 0
        indices = [lookup[color_word(p)] for p in f['pixels']]
        banks = {'native': (record['native_palette_group'], source)}
        for name, path in f.get('palette_variants', {}).items():
            banks[name] = (record['palette_variants'][name],
                           json.loads((ASSETS / path).read_text()))
        urls = {}
        for name, (bank, palette) in banks.items():
            pixels = [rgba(palette[i]) for i in indices]
            w, h = f['w'], f['h']
            src = proof / f'{index:04d}-{name}-source.png'
            png(src, w, h, pixels)
            doubled = proof / f'{index:04d}-{name}-2x.png'
            png(doubled, w * 2, h * 2, [pixels[y // 2 * w + x // 2]
                                      for y in range(h * 2) for x in range(w * 2)])
            dw, dh, raw = decode_png(doubled.read_bytes())
            gpu = BUILD / 'gpu-readback' / f'{index:04d}-{bank}.png'
            gw, gh, readback = decode_png(gpu.read_bytes())
            for y in range(dh):
                for x in range(dw):
                    expected = readback[(y // 2 * gw + x // 2) * 4:
                                        (y // 2 * gw + x // 2 + 1) * 4]
                    if raw[(y * dw + x) * 4:(y * dw + x + 1) * 4] != expected:
                        raise ValueError(f'{f["name"]}/{name}: exact2x mismatch{x},{y}')
                    checked += 1
            urls[name] = {'source': embed(src), 'gpu': embed(gpu)}
        preferred = f.get('preferred_element', 'native')
        if preferred == 'iron':
            preferred = 'native'
        display_frames.append(f | {'pixels': [rgba(banks[preferred][1][i]) for i in indices]})
        data.append({'name': f['name'], 'w': f['w'], 'h': f['h'], 'anchor': f['anchor'],
                     'images': urls, 'default': preferred})
        groups[f['actor'] + '/' + f['direction'] + '/' + f['action']].append(index)
    rigs = assemble(frames)
    for f in rigs:
        index = len(data)
        path = proof / f'rig-{index}.png'
        png(path, f['w'], f['h'], f['pixels'])
        data.append({'name': f['actor'] + '/' + f['action'], 'w': f['w'], 'h': f['h'],
                     'anchor': f['anchor'], 'images': {'native': {'source': embed(path),
                     'gpu': embed(path)}}, 'default': 'native', 'assembled': True})
        groups[f['actor'] + '/' + f['direction'] + '/' + f['action']].append(index)
    actors = ('keeper', 'tide_biter', 'salt_charger', 'drowned_watcher', 'reef_crab',
              'mist_jellyfish', 'lighthouse_guardian', 'tide_lord')
    lineup = [next(f for f in frames + rigs if f['actor'] == a and f['direction'] == 'down'
                   and f['action'] == ('phase1_idle' if a == 'tide_lord' else 'idle')
                   and f['frame'] == 0) for a in actors]
    width = sum(f['w'] + 20 for f in lineup)
    baseline = max(f['anchor'][1] for f in lineup) + 8
    height = baseline + max(f['h'] - f['anchor'][1] for f in lineup) + 8
    canvas = [(25, 38, 56, 255)] * (width * height)
    left = 10
    for f in lineup:
        draw(canvas, width, f, left, baseline - f['anchor'][1])
        left += f['w'] + 20
    lineuppath = OUTPUT / 'size-lineup-8x.png'
    png(lineuppath, width * 8, height * 8,
        [canvas[y // 8 * width + x // 8] for y in range(height * 8) for x in range(width * 8)])
    repairs = []
    for item in json.loads((ASSETS / 'production-06a2d.json').read_text()):
        if not item['include_frames']:
            continue
        s = json.loads((ASSETS / item['metadata']).read_text())
        if not (s.get('head_copies') or s.get('row_edits') or s.get('final_pixel_edits')):
            continue
        stem = s['name']
        before = ASSETS / (stem + '-before-repair.png')
        after = ASSETS / (stem + '-native.png')
        w, h, a = decode_png(before.read_bytes())
        _, _, b = decode_png(after.read_bytes())
        path = proof / (stem + '-diff.png')
        png(path, w, h, [(255, 70, 150, 255) if a[i:i + 4] != b[i:i + 4]
                         else (0, 0, 0, 0) for i in range(0, len(a), 4)])
        repairs.append({'name': stem, 'before': embed(before), 'after': embed(after),
                        'diff': embed(path)})
    movie = video(display_frames, rigs)
    page = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<title>06a-2d海岸素材检视</title><style>
body{background:#142033;color:#f4e4c8;font:16px/1.6 system-ui;margin:24px}h1,h2{color:#77ddd7}
select,button{font:inherit;background:#20344a;color:white;padding:7px;max-width:95%}
canvas,img{image-rendering:pixelated}canvas{background:#1c2d40}.row,.grid{display:flex;gap:12px;
flex-wrap:wrap}article{padding:12px;background:#1c2d40}article small{display:block}
.scroll{overflow:auto}.pair{display:flex;gap:24px}.grid canvas{width:160px;height:160px}
#views canvas{width:224px;height:224px}video{width:min(960px,100%)}
</style><h1>06a-2d · 海岸素材检视</h1><p>首版：守火人 / 余烬剑 / 余火杖 / 海岸。
这是素材检视和素材预览，不是游戏截图或游戏录像。组装头目仅用于检查部件关系。</p>'''
    page += (f'<p>PC源帧{len(frames)}；DDR {packet["ddr_library_bytes"]:,} B；'
             f'GPU {packet["gpu_readback_texels"]:,}纹素RGBA回读；精确2×{checked:,}像素一致。</p>'
             f'<p>普通波上界{budget["ordinary_wave_estimate_bytes"]:,} B；'
             f'Boss波{budget["boss_wave_estimate_bytes"]:,} B /147456 B。'
             '场景种类数为约定假设；完整固定区由06b接入后实测。</p>')
    page += '<h2>动作与五朝向</h2><select id="actor"></select> <select id="action"></select>'
    page += '<select id="element"><option value="default">默认色板</option>'
    page += ''.join(f'<option>{e}</option>'
                    for e in ('native', 'ember', 'tide', 'iron', 'star', 'shadow'))
    page += '</select><div class="row" id="views">'
    for d in DIRECTIONS:
        page += f'<article>{d}<br><canvas data-dir="{d}"></canvas><small></small></article>'
    page += '</div><h2>原生源像素 / GPU模型回读 · 8×</h2>'
    page += '<p>逐帧选择；左源图，右实际GPU回读。组装检视不列入GPU对比。</p>'
    page += '<select id="comparison"></select><div class="scroll"><div class="pair">'
    page += '<canvas id="source"></canvas><canvas id="gpu"></canvas></div></div>'
    page += '<h2>相同倍率并排体型 · 8× / 脚锚对齐</h2><p>' + ' / '.join(actors) + '</p>'
    page += '<div class="scroll"><img src="' + embed(lineuppath) + '"></div>'
    page += '<h2>特效与粒子动图 · 五元素色板</h2><p>粒子使用加色叠加；大特效按当前帧流式装载。</p>'
    page += '<div class="grid" id="effects"></div><h2>地形6×6随机自动拼接</h2>'
    for biome in ('sand', 'shallow', 'reef', 'ruins', 'grass'):
        page += '<details><summary>' + biome + '</summary><img src="' + embed(
            OUTPUT / f'terrain-{biome}-sample6x6-4x.png') + '"></details>'
    page += '<h2>修整前 / 修整后 / 实际差分</h2>'
    for repair in repairs:
        page += '<details><summary>' + repair['name'] + '</summary><div class="row">'
        page += ''.join('<img style="width:1024px" src="' + repair[k] + '">'
                        for k in ('before', 'after', 'diff')) + '</div></details>'
    page += '<h2>30秒素材预览</h2><video controls loop src="data:video/mp4;base64,'
    page += base64.b64encode(movie.read_bytes()).decode() + '"></video><script>'
    page += 'const data=' + json.dumps(data) + ';const groups=' + json.dumps(groups) + ';'
    page += '''const cache={};function image(url){if(!cache[url]){const i=new Image();i.src=url;
cache[url]=i}return cache[url]}const actor=document.querySelector('#actor');
const action=document.querySelector('#action'),element=document.querySelector('#element');
const comparison=document.querySelector('#comparison');let tick=0;
for(const a of [...new Set(Object.keys(groups).map(k=>k.split('/')[0]))])actor.add(new Option(a,a));
function actions(){action.replaceChildren();for(const a of [...new Set(Object.keys(groups)
.filter(k=>k.startsWith(actor.value+'/')).map(k=>k.split('/')[2]))])action.add(new Option(a,a))}
actor.onchange=actions;actions();data.forEach((f,i)=>{if(!f.assembled)
comparison.add(new Option(f.name+' ['+f.w+'×'+f.h+']',i))});
function texture(f){let e=element.value==='default'?f.default:element.value;
return f.images[e]||f.images.native}function paint(c,f,kind,zoom){const url=texture(f)[kind];
const i=image(url);c.width=f.w*zoom;c.height=f.h*zoom;const x=c.getContext('2d');
x.imageSmoothingEnabled=false;if(i.complete)x.drawImage(i,0,0,c.width,c.height)}
function animated(c,ids,additive=false){c.width=c.height=224;const x=c.getContext('2d');
x.imageSmoothingEnabled=false;if(!ids){x.fillStyle='#eee';x.fillText('此动作使用固定方向或不适用',6,100);
return}const f=data[ids[tick%ids.length]],i=image(texture(f).source);
const z=Math.min(8,Math.max(1,Math.floor(184/Math.max(f.w,f.h))));
x.globalCompositeOperation=additive?'lighter':'source-over';if(i.complete)
x.drawImage(i,Math.floor((224-f.w*z)/2),Math.floor((224-f.h*z)/2),f.w*z,f.h*z)}
const fx=[];for(const [key,ids] of Object.entries(groups)){const [a,d,act]=key.split('/');
if(['coast_small_fx','coast_large_fx','coast_particles','coast_light','coast_ui_icons',
'coast_card_borders'].includes(a)){const card=document.createElement('article');
card.innerHTML='<small>'+a+'/'+act+'</small><canvas></canvas>';
document.querySelector('#effects').append(card);fx.push([card.querySelector('canvas'),ids,
a==='coast_particles'])}}
function render(){for(const c of document.querySelectorAll('#views canvas')){
let d=c.dataset.dir;if(actor.value==='mist_jellyfish')d=action.value==='walk'&&
!['down','up'].includes(d)?'lean_right':'down';
const ids=groups[actor.value+'/'+d+'/'+action.value];animated(c,ids);
c.nextElementSibling.textContent=ids?ids.length+'帧':'固定朝向或不适用'}
const f=data[Number(comparison.value)];paint(document.querySelector('#source'),f,'source',8);
paint(document.querySelector('#gpu'),f,'gpu',8);
for(const [c,ids,add] of fx)animated(c,ids,add);tick++}
setInterval(render,160);render();</script></html>'''
    (OUTPUT / 'index.html').write_text(page)
    (BUILD / 'preview.json').write_text(json.dumps({'exact_2x_pixels': checked,
        'pc_frames': len(frames), 'assembled_review_frames': len(rigs),
        'preview_seconds': 30, 'video_size': [960, 540],
        'scope': 'material preview, not game footage'}, indent=2) + '\n')
    print(f'PASS exact2x {checked} pixels; {len(frames)} source frames;30s material preview')


if __name__ == '__main__':
    main()
