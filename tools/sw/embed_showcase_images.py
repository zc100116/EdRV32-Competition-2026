#!/usr/bin/env python3
"""embed_showcase_images.py — showcase design §5: embed PNG art as ARGB8888 LVGL images.

Every *.png in the asset directory becomes `const lv_image_dsc_t <prefix>_<stem>`
(stem lower-case, '-' -> '_'), non-premultiplied ARGB8888 as DISP L1 and RND expect.
Host build tool; standard-library PNG decoding from png2c.
"""
import argparse
from pathlib import Path

from png2c import decode_png


def image_argb8888_c(name, width, height, rgba):
    """Emit one ARGB8888 LVGL image descriptor; words are 0xAARRGGBB little-endian."""
    words = [rgba[i + 3] << 24 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2]
             for i in range(0, len(rgba), 4)]
    lines = [f'static const uint32_t {name}_pixels[] = {{']
    for i in range(0, len(words), 8):
        lines.append('    ' + ','.join(f'0x{v:08x}' for v in words[i:i + 8]) + ',')
    lines.extend(['};', f'const lv_image_dsc_t {name} = {{',
                  '    .header = {.magic = LV_IMAGE_HEADER_MAGIC,',
                  f'        .cf = LV_COLOR_FORMAT_ARGB8888, .w = {width}, .h = {height},',
                  f'        .stride = {width * 4}}},',
                  f'    .data_size = sizeof({name}_pixels),',
                  f'    .data = (const uint8_t *){name}_pixels', '};'])
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('assets', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--prefix', required=True)
    args = parser.parse_args()
    lines = [f'/* Generated from {args.assets.name} PNG files by embed_showcase_images.py. */',
             '#include "lvgl.h"']
    for path in sorted(args.assets.glob('*.png')):
        width, height, rgba = decode_png(path.read_bytes())
        name = f'{args.prefix}_{path.stem.lower().replace("-", "_")}'
        lines.extend(image_argb8888_c(name, width, height, rgba))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
