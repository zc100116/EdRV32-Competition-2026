#!/usr/bin/env python3
"""preview_streaming_probe.py — ART-3 tech 7 partial source inspection.
Standard-library host tool; writes a 30-second asset preview, never game footage.
Requires ffmpeg on PATH. Uses saved native pixels with integer display scaling.
"""
import base64
import subprocess

from coast_assets import ASSETS
from normalize_sample import decode_png, png
from preview_coast import walk_comparison
from probe_coast_streaming import OUTPUT


def main():
    images = [decode_png((ASSETS / name).read_bytes()) for name in
              ('keeper-down-v3-native.png', 'reef-crab-down-06a2-native.png')]
    for index in range(8):
        canvas = [(232, 193, 129, 255)] * (640 * 360)
        for actor, (width, height, raw) in enumerate(images):
            cell_x = index % 4 * 64
            cell_y = index // 4 * 64
            for y in range(64):
                for x in range(64):
                    pixel = tuple(raw[((cell_y + y) * width + cell_x + x) * 4:
                                      ((cell_y + y) * width + cell_x + x) * 4 + 4])
                    if pixel[3]:
                        for dy in range(4):
                            for dx in range(4):
                                px = 40 + actor * 300 + x * 4 + dx
                                py = 40 + y * 4 + dy
                                canvas[py * 640 + px] = pixel
        png(OUTPUT / f'preview-{index:02d}.png', 640, 360, canvas)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', '8', '-loop', '1',
                    '-i', str(OUTPUT / 'preview-%02d.png'), '-t', '30', '-an',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
                    str(OUTPUT / 'partial-assets-30s.mp4')], check=True)
    comparisons = [('down', 'keeper-down-v3'), ('up', 'keeper-up-v3')]
    page = (OUTPUT / 'index.html').read_text()
    for direction, current in comparisons:
        encoded = walk_comparison(direction, current)
        page += (f'<h2>{direction}: retained 06a front/back walk repair, 8x</h2>'
                 f'<img src="data:image/png;base64,{encoded}" '
                 f'alt="{direction} walk before and after">')
    video = base64.b64encode((OUTPUT / 'partial-assets-30s.mp4').read_bytes()).decode()
    page += ('<h2>30秒局部素材预览；不是游戏录像</h2><video controls loop '
             f'src="data:video/mp4;base64,{video}"></video>')
    (OUTPUT / 'index.html').write_text(page)
    print('Partial preview: 640x360, 30 seconds, 8fps; no game simulation or rendering claims')


if __name__ == '__main__':
    main()
