#!/usr/bin/env python3
"""png2c.py — showcase design §5: shared PNG decoding and RGB565 C images.
Host build tool; standard-library decoding shared with gen_sim_games.
"""
from pathlib import Path
import struct
import sys
import zlib


def decode_png(data):
    """Decode the specified 8-bit RGB/RGBA noninterlaced PNG subset."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('icon is not PNG')
    offset = 8
    compressed = bytearray()
    while offset < len(data):
        length, kind = struct.unpack_from('>I4s', data, offset)
        chunk = data[offset + 8:offset + 8 + length]
        offset += length + 12
        if kind == b'IHDR':
            width, height, depth, color, method, filtering, interlace = struct.unpack(
                '>IIBBBBB', chunk)
            if depth != 8 or color not in (2, 6) or method or filtering or interlace:
                raise ValueError('PNG requires 8-bit RGB/RGBA, noninterlaced')
        elif kind == b'IDAT':
            compressed.extend(chunk)
        elif kind == b'IEND':
            break
    channels = 3 if color == 2 else 4
    stride = width * channels
    raw = zlib.decompress(compressed)
    previous = bytearray(stride)
    rgba = bytearray()
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            above = previous[x]
            corner = previous[x - channels] if x >= channels else 0
            if kind == 0:
                predictor = 0
            elif kind == 1:
                predictor = left
            elif kind == 2:
                predictor = above
            elif kind == 3:
                predictor = (left + above) // 2
            elif kind == 4:
                p = left + above - corner
                distances = (abs(p - left), abs(p - above), abs(p - corner))
                predictor = (left, above, corner)[distances.index(min(distances))]
            else:
                raise ValueError(f'unsupported PNG filter {kind}')
            row[x] = (row[x] + predictor) & 255
        for x in range(0, stride, channels):
            rgba.extend(row[x:x + 3])
            rgba.append(row[x + 3] if channels == 4 else 255)
        previous = row
    return width, height, bytes(rgba)


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
