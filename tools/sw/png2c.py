#!/usr/bin/env python3
"""png2c.py — showcase design §5: sample PNGs to 960x540 RGB565 C arrays.
Host build tool; standard-library PNG decoding shared with pack_games.
"""
from pathlib import Path
import sys
from pack_games import decode_png

output = Path(sys.argv[1])
assets = Path(__file__).resolve().parents[2] / 'sw/apps/showcase/sim/assets'
lines = ['/* Generated sample photos: desktop simulator only. */', '#include "lvgl.h"']
for name, filename in [('street', 'street-scene.png'), ('indoor', 'indoor-scene.png')]:
    width, height, rgba = decode_png((assets / filename).read_bytes())
    pixels = []
    for y in range(540):
        for x in range(960):
            i = ((y * height // 540) * width + x * width // 960) * 4
            r, g, b = rgba[i:i + 3]
            pixels.append((r >> 3) << 11 | (g >> 2) << 5 | b >> 3)
    lines.append(f'static const uint16_t {name}_pixels[] = {{')
    for i in range(0, len(pixels), 16):
        lines.append('    ' + ','.join(f'0x{v:04x}' for v in pixels[i:i + 16]) + ',')
    lines.extend(['};', f'const lv_image_dsc_t sim_{name} = {{',
                  '    .header = {.magic = LV_IMAGE_HEADER_MAGIC,',
                  '        .cf = LV_COLOR_FORMAT_RGB565, .w = 960, .h = 540, .stride = 1920},',
                  f'    .data_size = sizeof({name}_pixels),',
                  f'    .data = (const uint8_t *){name}_pixels', '};'])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text('\n'.join(lines) + '\n')
