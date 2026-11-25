#!/usr/bin/env python3
"""preview_compact_coast.py — ART-3 06a-2c source inspection, tech 7.
Host-only standard-library media export, with ffmpeg for the 30-second MP4.
Shows incomplete artwork and exact integer enlargement, never game footage.
"""
import base64
import json
from pathlib import Path
import subprocess

from coast_assets import ASSETS, DIRECTIONS
from compact_coast_frames import BUILD, OUTPUT, load_frames
from normalize_sample import decode_png, png
from preview_coast import walk_comparison


def embedded(path):
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    keeper_stems = ['keeper-down-v3', 'keeper-down-right-v2', 'keeper-right-v2',
                    'keeper-up-right-v2', 'keeper-up-v3']
    sources = json.loads((ASSETS / 'coast-06a2c-sources.json').read_text())
    names = [('守火人 / ' + direction, stem) for direction, stem
             in zip(DIRECTIONS, keeper_stems)]
    labels = {'tide_biter': '潮啮（尺寸未通过）', 'salt_charger': '盐冲者',
              'drowned_watcher': '溺望者', 'mist_jellyfish': '雾水母',
              'reef_crab': '礁壳蟹'}
    for source in sources:
        sheet = json.loads((ASSETS / source['metadata']).read_text())
        names.append((labels[source['actor']] + ' / down', sheet['name']))
    images = {}
    checked = 0
    for label, stem in names:
        width, height, raw = decode_png((ASSETS / (stem + '-native.png')).read_bytes())
        pixels = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
        images[stem] = width, height, pixels
        doubled = [pixels[y // 2 * width + x // 2]
                   for y in range(height * 2) for x in range(width * 2)]
        target = OUTPUT / (stem + '-2x.png')
        png(target, width * 2, height * 2, doubled)
        dw, dh, decoded = decode_png(target.read_bytes())
        for y in range(dh):
            for x in range(dw):
                expected = bytes(pixels[y // 2 * width + x // 2])
                actual = decoded[(y * dw + x) * 4:(y * dw + x + 1) * 4]
                if actual != expected:
                    raise ValueError(f'{target.name}: exact 2x mismatch at {x},{y}')
                checked += 1
    frame_2x_pixels = 0
    frame_output = BUILD / 'frames-2x'
    frame_output.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(load_frames()):
        width, height, pixels = frame['w'], frame['h'], frame['pixels']
        target = frame_output / f'{index:03d}.png'
        png(target, width * 2, height * 2,
            [pixels[y // 2 * width + x // 2]
             for y in range(height * 2) for x in range(width * 2)])
        dw, dh, decoded = decode_png(target.read_bytes())
        for y in range(dh):
            for x in range(dw):
                expected = bytes(pixels[y // 2 * width + x // 2])
                if decoded[(y * dw + x) * 4:(y * dw + x + 1) * 4] != expected:
                    raise ValueError(f'{frame["name"]}: exact 2x mismatch at {x},{y}')
                frame_2x_pixels += 1
    # Same scale and foot baseline for all six subjects; transparent margins stay intact.
    comparison_stems = [keeper_stems[0]] + [
        json.loads((ASSETS / s['metadata']).read_text())['name'] for s in sources]
    comparison = [(31, 45, 64, 255)] * (384 * 64)
    for actor, stem in enumerate(comparison_stems):
        width, _, pixels = images[stem]
        for y in range(64):
            for x in range(64):
                p = pixels[y * width + x]
                if p[3]:
                    comparison[y * 384 + actor * 64 + x] = p
    png(OUTPUT / 'size-lineup-8x.png', 3072, 512,
        [comparison[y // 8 * 384 + x // 8] for y in range(512) for x in range(3072)])
    for index in range(8):
        canvas = [(31, 45, 64, 255)] * (640 * 360)
        for actor, stem in enumerate(comparison_stems):
            width, _, pixels = images[stem]
            for y in range(64):
                for x in range(64):
                    p = pixels[(index // 4 * 64 + y) * width + index % 4 * 64 + x]
                    if p[3]:
                        for dy in range(2):
                            for dx in range(2):
                                px = 48 + actor % 3 * 192 + x * 2 + dx
                                py = 32 + actor // 3 * 160 + y * 2 + dy
                                canvas[py * 640 + px] = p
        png(OUTPUT / f'preview-{index:02d}.png', 640, 360, canvas)
    subprocess.run([str(Path.home() / '.local/opt/video/bin/ffmpeg'),
                    '-v', 'error', '-y', '-framerate', '8', '-stream_loop', '-1',
                    '-i', str(OUTPUT / 'preview-%02d.png'), '-t', '30', '-an',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
                    str(OUTPUT / 'partial-assets-30s.mp4')], check=True)
    result = json.loads((BUILD / 'frames.json').read_text())
    cards = []
    for label, stem in names:
        cards.append('<article><h3>' + label + '</h3><canvas width="64" height="64" '
                     f'data-sheet="{embedded(ASSETS / (stem + "-native.png"))}"></canvas>'
                     '<details><summary>原生网格 / 8x 放大（横向滚动）</summary>'
                     f'<img class="sheet" src="{embedded(ASSETS / (stem + "-native.png"))}"'
                     ' width="2048" height="1024"></details></article>')
    page = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<title>06a-2c 紧凑帧库检查点</title><style>
*{box-sizing:border-box}body{margin:32px;background:#142033;color:#f6e4c4;
font:16px/1.6 system-ui,sans-serif}h1{color:#77ddd7}h2{margin-top:40px}
.notice{padding:18px;background:#482e3e;border-left:4px solid #ffa173}
.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px}
article{background:#1f2d40;padding:12px;overflow:auto}canvas,img{image-rendering:pixelated}
canvas{width:100%;max-width:256px;aspect-ratio:1}details{overflow:auto}
.lineup{overflow:auto}video{width:min(100%,960px)}.sheet{max-width:none}
</style><h1>06a-2c · 海岸紧凑帧库</h1>
<p class="notice">容量检查点，整包未完成。以下是素材检视与素材预览，不是游戏截图或游戏录像。
新小怪仅正面待机/移动；其余朝向、攻击/受击/死亡、头目/Boss、地图与铸铁匠未完成。
潮啮待机高度38–40px，超出24–30px，不能当合格成群小怪；未缩图掩盖。</p>'''
    page += (f'<p>已存 {result["source_frames"]} 帧，紧凑 DDR 局部库 '
             f'{result["ddr_library_bytes"]:,} B。GPU 合法页逐纹素回读通过；'
             f'2x 逐像素一致：10张表{checked:,}像素，全部180帧{frame_2x_pixels:,}像素。</p>'
             '<p>容量证明：盐冲者1848 + 溺望者1760 + 雾水母1672 + 礁壳蟹2080 = '
             '7360 B；×5动作×5方向 = 184000 B，超147456 B至少36544 B。'
             '未含潮啮、主角、宠物、精英及场景，完整上界与固定区未测。</p>')
    page += '<h2>并排体型 · 同脚底同倍率</h2><p>守火人、潮啮、盐冲者、溺望者、雾水母、礁壳蟹</p>'
    page += '<div class="lineup"><img src="' + embedded(
        OUTPUT / 'size-lineup-8x.png') + '" width="3072" height="512"></div>'
    page += '<h2>已保留守火人五朝向 · 待机与步态循环</h2><div class="grid">'
    page += ''.join(cards[:5]) + '</div><h2>新小怪正面样张 · 待机与移动循环</h2>'
    page += '<div class="grid">' + ''.join(cards[5:]) + '</div>'
    for direction, stem in [('down', keeper_stems[0]), ('up', keeper_stems[4])]:
        encoded = walk_comparison(direction, stem)
        page += (f'<h2>{direction} · 保留06a步态修整 · 8x前后对比</h2>'
                 f'<div class="lineup"><img src="data:image/png;base64,{encoded}"></div>')
    video = base64.b64encode((OUTPUT / 'partial-assets-30s.mp4').read_bytes()).decode()
    page += '<h2>30秒局部素材预览</h2><video controls loop src="data:video/mp4;base64,'
    page += video + '"></video><script>'
    page += '''const sprites=[...document.querySelectorAll('canvas')].map(c=>{
const i=new Image();i.src=c.dataset.sheet;return {c,i}});let tick=0;
function draw(){for(const {c,i} of sprites){if(!i.complete)continue;
const x=c.getContext('2d');x.clearRect(0,0,64,64);x.imageSmoothingEnabled=false;
x.drawImage(i,tick%4*64,Math.floor(tick/4)*64,64,64,0,0,64,64)}tick=(tick+1)%8}
setInterval(draw,160);draw();</script></html>'''
    (OUTPUT / 'index.html').write_text(page)
    (BUILD / 'preview.json').write_text(json.dumps(
        {'exact_2x_sheet_pixels': checked, 'exact_2x_frame_pixels': frame_2x_pixels,
         'preview_seconds': 30,
         'preview_resolution': [640, 360], 'scope': 'partial asset preview'}) + '\n')
    print(f'PASS exact 2x: sheets {checked}, frames {frame_2x_pixels} pixels; HTML/30s preview')


if __name__ == '__main__':
    main()
