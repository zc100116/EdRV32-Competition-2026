#!/usr/bin/env python3
"""preview_coast_production.py — ART-3 06a-2d native source review, tech 7.
Standard-library exact 2x checks and self-contained HTML; ffmpeg encodes the
30-second material preview. This tool does not execute the game or GPU renderer.
"""
import base64
from collections import Counter, defaultdict
import json
from pathlib import Path
import subprocess
import sys

from coast_assets import ASSETS, ROOT
from coast_production import BUILD, OUTPUT, fpga_frame, load_native_frames
from normalize_sample import decode_png, png

sys.path.insert(0, str(ROOT / 'sw/apps/ember_isles/tools'))
from font_convert import read_glyphs

LABELS = {'keeper': '守火人', 'smith': '铸铁匠', 'tide_biter': '潮啮',
          'salt_charger': '盐冲者', 'drowned_watcher': '溺望者',
          'reef_crab': '礁壳蟹', 'mist_jellyfish': '雾水母',
          'lighthouse_guardian_body': '灯塔守卫身体'}


def embed(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def caption(canvas, text, x0, y0, glyphs, color=(119, 221, 215, 255)):
    for char in text:
        advance, rows = glyphs[ord(char)]
        for y, row in enumerate(rows):
            for x in range(12):
                if row & (1 << (11 - x)):
                    canvas[(y0 + y) * 640 + x0 + x] = color
        x0 += advance


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = json.loads((BUILD / 'frames.json').read_text())
    converted = {frame['name'] for frame in result['frames']}
    frames = [frame for frame in load_native_frames() if frame['name'] in converted]
    estimate = json.loads((BUILD / 'budget-estimate.json').read_text())
    groups = defaultdict(list)
    images, repairs = {}, []
    checked = 0
    doubled_output = BUILD / 'frames-2x'
    doubled_output.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames):
        width, height, pixels = frame['w'], frame['h'], frame['pixels']
        path = doubled_output / f'{index:04d}.png'
        png(path, width * 2, height * 2,
            [pixels[y // 2 * width + x // 2]
             for y in range(height * 2) for x in range(width * 2)])
        dw, dh, raw = decode_png(path.read_bytes())
        for y in range(dh):
            for x in range(dw):
                if raw[(y * dw + x) * 4:(y * dw + x + 1) * 4] != bytes(
                        pixels[y // 2 * width + x // 2]):
                    raise ValueError(f'{frame["name"]}: 2x pixel mismatch at {x},{y}')
                checked += 1
        stem = frame['source_sheet']
        images[stem] = embed(ASSETS / (stem + '-native.png'))
        groups[frame['actor'] + '/' + frame['direction'] + '/' + frame['action']].append(
            {k: frame[k] for k in ('source_sheet', 'source_cell', 'cell_size', 'frame')})
    for group in groups.values():
        group.sort(key=lambda frame: frame['frame'])
    for item in json.loads((ASSETS / 'production-06a2d.json').read_text()):
        if not item['include_frames']:
            continue
        sheet = json.loads((ASSETS / item['metadata']).read_text())
        if not (sheet.get('head_copies') or sheet.get('row_edits')
                or sheet.get('final_pixel_edits')):
            continue
        stem = sheet['name']
        before = ASSETS / (stem + '-before-repair.png')
        after = ASSETS / (stem + '-native.png')
        width, height, a = decode_png(before.read_bytes())
        _, _, b = decode_png(after.read_bytes())
        delta = [(255, 70, 150, 255) if a[i:i + 4] != b[i:i + 4] else (0, 0, 0, 0)
                 for i in range(0, len(a), 4)]
        target = BUILD / (stem + '-repair-diff.png')
        png(target, width, height, delta)
        images['before:' + stem] = embed(before)
        images['diff:' + stem] = embed(target)
        repairs.extend({'sheet': stem, 'cell': c['cell'], 'size': sheet['cell'],
                        'label': stem + '/' + c['id']}
                       for c in sheet['cells'] if c['action'] in item['actions'])
    # Every figure uses the same native scale and foot baseline.
    actors = list(dict.fromkeys(f['actor'] for f in frames))
    lineup_frames = [next(f for f in frames if f['actor'] == actor
                         and f['direction'] == 'down' and f['action'] == 'idle'
                         and f['frame'] == 0)
                     for actor in actors if any(f['actor'] == actor
                         and f['direction'] == 'down' and f['action'] == 'idle' for f in frames)]
    lineup_width = sum(f['w'] + 16 for f in lineup_frames)
    lineup_height = max(f['h'] for f in lineup_frames) + 16
    lineup = [(25, 38, 56, 255)] * (lineup_width * lineup_height)
    left = 8
    for frame in lineup_frames:
        top = lineup_height - 8 - frame['h']
        for y in range(frame['h']):
            for x in range(frame['w']):
                p = frame['pixels'][y * frame['w'] + x]
                if p[3]:
                    lineup[(top + y) * lineup_width + left + x] = p
        left += frame['w'] + 16
    lineup_path = OUTPUT / 'size-lineup-8x.png'
    png(lineup_path, lineup_width * 8, lineup_height * 8,
        [lineup[y // 8 * lineup_width + x // 8]
         for y in range(lineup_height * 8) for x in range(lineup_width * 8)])
    # A neutral specimen board, no simulated combat or gameplay footage.
    video_groups = defaultdict(list)
    for frame in frames:
        if frame['direction'] == 'down':
            video_groups[frame['actor'], frame['action']].append(frame)
    clips = list(video_groups.values())
    for clip in clips:
        clip.sort(key=lambda f: f['frame'])
    labels = [LABELS.get(c[0]['actor'], c[0]['actor']) + ' ' + c[0]['action']
              for c in clips]
    title = '06a-2d 素材预览 · 非游戏录像'
    glyphs = read_glyphs(set(map(ord, title + ''.join(labels))))
    video_frames = BUILD / 'video-frames'
    video_frames.mkdir(parents=True, exist_ok=True)
    for tick in range(240):
        canvas = [(25, 38, 56, 255)] * (640 * 360)
        caption(canvas, title, 16, 12, glyphs)
        for panel in range(8):
            clip_index = (tick // 48 * 8 + panel) % len(clips)
            clip = clips[clip_index]
            caption(canvas, labels[clip_index], 16 + panel % 4 * 156,
                    36 + panel // 4 * 152, glyphs)
            frame = clip[tick % len(clip)]
            scale = max(1, min(2, 112 // max(frame['w'], frame['h'])))
            px = 16 + panel % 4 * 156 + (128 - frame['w'] * scale) // 2
            py = 48 + panel // 4 * 152 + 120 - frame['h'] * scale
            for y in range(frame['h']):
                for x in range(frame['w']):
                    p = frame['pixels'][y * frame['w'] + x]
                    if p[3]:
                        for dy in range(scale):
                            for dx in range(scale):
                                canvas[(py + y * scale + dy) * 640
                                       + px + x * scale + dx] = p
        png(video_frames / f'{tick:03d}.png', 640, 360, canvas)
    video = OUTPUT / 'assets-preview-30s.mp4'
    subprocess.run([str(Path.home() / '.local/opt/video/bin/ffmpeg'), '-v', 'error',
                    '-y', '-framerate', '8', '-i', str(video_frames / '%03d.png'),
                    '-t', '30', '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
                    str(video)], check=True)
    counts = Counter(f['actor'] for f in frames)
    fpga_count = sum(fpga_frame(f) for f in frames)
    page = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<title>06a-2d 海岸素材检视</title><style>
*{box-sizing:border-box}body{background:#142033;color:#f4e4c8;font:16px/1.65 system-ui;
margin:28px}h1,h2{color:#77ddd7}.notice{background:#422c3d;padding:14px}
select{font:inherit;background:#20344a;color:#fff;padding:6px}.views{display:flex;gap:12px}
article{background:#1c2d40;padding:12px;min-width:200px}canvas,img{image-rendering:pixelated}
.pose{width:224px;height:224px}small{display:block}.scroll{overflow:auto}.repairs{display:flex;
gap:12px}.repair{width:512px;height:512px}video{width:min(100%,960px)}
</style><h1>06a-2d · 海岸素材检视</h1>
<p class="notice">分批生产进行中。这里只展示已经存在的素材；缺失方向或动作明确标注。
这是素材检视和素材预览，不是游戏截图或游戏录像。PC 保留完整动作，FPGA 另选子集。</p>'''
    page += (f'<p>当前 PC {len(frames)} 帧 / DDR {result["ddr_library_bytes"]:,} B；'
             f'FPGA 表 {fpga_count} 帧。GPU {result["gpu_readback_texels"]:,} 纹素回读通过，'
             f'2×逐像素一致 {checked:,} 像素。</p>'
             f'<p>FPGA普通波估算 {estimate["ordinary_wave_estimate_bytes"]:,} B，'
             f'Boss波估算 {estimate["boss_wave_estimate_bytes"]:,} B / 147456 B。'
             '含未产项估算，完整固定区和全包仍未完成。</p>')
    page += '<h2>动作与五向检视</h2><p><select id="actor"></select> '
    page += '<select id="action"></select></p><div class="scroll"><div class="views">'
    for d, label in [('down', '下'), ('down_right', '右下'), ('right', '右'),
                     ('up_right', '右上'), ('up', '上')]:
        page += f'<article><h3>{label}</h3><canvas class="pose" data-dir="{d}"></canvas>'
        page += '<small></small></article>'
    page += '</div></div><h2>同倍率并排体型 · 8×</h2><p>'
    page += '、'.join(LABELS.get(f['actor'], f['actor']) for f in lineup_frames) + '</p>'
    page += '<div class="scroll"><img src="' + embed(lineup_path) + '"></div>'
    page += '<h2>逐帧原生像素修整 · 原始 / 修后 / 差分 · 8×</h2>'
    page += '<p>粉色只表示像素发生变化；坐标标注在源表元数据中。</p><select id="repair"></select>'
    page += '<div class="scroll"><div class="repairs">'
    page += ''.join('<article>' + s + '<canvas class="repair"></canvas></article>'
                    for s in ('修前', '修后', '差分')) + '</div></div>'
    page += '<h2>30秒阶段素材预览</h2><video controls loop src="data:video/mp4;base64,'
    page += base64.b64encode(video.read_bytes()).decode() + '"></video><script>'
    page += 'const data=' + json.dumps({'groups': groups, 'images': images,
                                       'repairs': repairs, 'labels': LABELS,
                                       'counts': counts}, ensure_ascii=False) + ';'
    page += '''const imgs={};for(const [k,v] of Object.entries(data.images)){
const i=new Image();i.src=v;imgs[k]=i}const actor=document.querySelector('#actor');
const action=document.querySelector('#action');const repair=document.querySelector('#repair');
for(const a of Object.keys(data.counts)){actor.add(new Option(data.labels[a]||a,a))}
function actions(){action.replaceChildren();const acts=[...new Set(Object.keys(data.groups)
.filter(k=>k.startsWith(actor.value+'/')).map(k=>k.split('/')[2]))];
for(const a of acts)action.add(new Option(a,a))}actor.onchange=actions;actions();
data.repairs.forEach((r,n)=>repair.add(new Option(r.label,n)));let tick=0;
function paint(c,stem,cell,size){c.width=size[0];c.height=size[1];const x=c.getContext('2d');
x.imageSmoothingEnabled=false;x.clearRect(0,0,...size);const i=imgs[stem];
if(i.complete)x.drawImage(i,cell[0]*size[0],cell[1]*size[1],...size,0,0,...size)}
function draw(){for(const c of document.querySelectorAll('.pose')){let d=c.dataset.dir;
if(actor.value==='mist_jellyfish')d=action.value==='walk'&&d!=='down'&&d!=='up'?'lean_right':'down';
const a=data.groups[actor.value+'/'+d+'/'+action.value];const note=c.nextElementSibling;
if(!a){c.width=c.height=64;note.textContent='未制作';continue}
const f=a[tick%a.length];paint(c,f.source_sheet,f.source_cell,f.cell_size);
note.textContent=(actor.value==='mist_jellyfish'?'径向对称 / ':'')+a.length+'帧'}
const r=data.repairs[Number(repair.value)];if(r){const cs=document.querySelectorAll('.repair');
['before:','', 'diff:'].forEach((p,n)=>paint(cs[n],p+r.sheet,r.cell,r.size))}tick++}
setInterval(draw,160);draw();</script></html>'''
    (OUTPUT / 'index.html').write_text(page)
    (BUILD / 'preview.json').write_text(json.dumps(
        {'exact_2x_pixels': checked, 'pc_frames': len(frames), 'fpga_frames': fpga_count,
         'preview_seconds': 30, 'scope': 'material preview, not game footage'}, indent=2) + '\n')
    print(f'PASS: exact2x {checked} pixels; PC {len(frames)}, FPGA {fpga_count}; 30s preview')


if __name__ == '__main__':
    main()
