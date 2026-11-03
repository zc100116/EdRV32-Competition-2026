#!/usr/bin/env python3
"""png2c.py — showcase design §5: shared PNG decoding and RGB565 C images.
Host build tool; standard-library decoding shared with pack_games.
"""
from pathlib import Path
import sys
from pack_games import decode_png


def resize_rgb565(source, width, height):
    """Nearest-neighbour resize, compositing RGBA over white for RGB565."""
    source_width, source_height, rgba = source
    pixels = []
    for y in range(height):
        for x in range(width):
            i = ((y * source_height // height) * source_width + x * source_width // width) * 4
            r, g, b, a = rgba[i:i + 4]
            r, g, b = ((v * a + 255 * (255 - a)) // 255 for v in (r, g, b))
            pixels.append((r >> 3) << 11 | (g >> 2) << 5 | b >> 3)
    return pixels


def image_c(name, pixels, width, height):
    """Emit an opaque RGB565 LVGL image descriptor and its pixel array."""
    lines = [f'static const uint16_t {name}_pixels[] = {{']
    for i in range(0, len(pixels), 16):
        lines.append('    ' + ','.join(f'0x{v:04x}' for v in pixels[i:i + 16]) + ',')
    lines.extend(['};', f'const lv_image_dsc_t {name} = {{',
                  '    .header = {.magic = LV_IMAGE_HEADER_MAGIC,',
                  f'        .cf = LV_COLOR_FORMAT_RGB565, .w = {width}, .h = {height},',
                  f'        .stride = {width * 2}}},',
                  f'    .data_size = sizeof({name}_pixels),',
                  f'    .data = (const uint8_t *){name}_pixels', '};'])
    return lines


def main():
    output = Path(sys.argv[1])
    assets = Path(__file__).resolve().parents[2] / 'sw/apps/showcase/sim/assets'
    lines = ['/* Generated sample photos: desktop simulator only. */', '#include "lvgl.h"']
    for name, filename in [('street', 'street-scene.png'), ('indoor', 'indoor-scene.png')]:
        source = decode_png((assets / filename).read_bytes())
        lines.extend(image_c(f'sim_{name}', resize_rgb565(source, 960, 540), 960, 540))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
