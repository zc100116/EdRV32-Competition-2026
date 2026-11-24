#!/usr/bin/env python3
"""normalize_sample.py — tech §5/§7, ART-2 imagegen pixel-grid normalization.
Host tool (no clock domain); standard-library PNG IO, palette and grid alignment.
No character geometry is drawn here: all visible clusters come from imagegen.
"""
from collections import Counter
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / 'tools/sw'))
from png2c import decode_png

ASSETS = ROOT / 'sw/apps/ember_isles/assets/art_sample'
OUTPUT = ROOT / 'outputs/ember_isles'


def chunk(kind, data):
    return (struct.pack('>I', len(data)) + kind + data
            + struct.pack('>I', zlib.crc32(kind + data)))


def png(path, width, height, pixels):
    raw = b''.join(b'\0' + bytes(v for p in pixels[y * width:(y + 1) * width] for v in p)
                   for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'
                     + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def expand(color):
    r, g, b, a = color
    return (r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2, a * 17)


def reduce_color(color):
    r, g, b, a = color
    return r >> 3, g >> 2, b >> 3, (a + 8) // 17


def palette_for(pixels, count):
    histogram = Counter(reduce_color(p) for p in pixels if p[3])
    boxes = [list(histogram)]
    while len(boxes) < count - 1:
        candidates = [(max(max(c[k] for c in box) - min(c[k] for c in box)
                           for k in range(3)) * sum(histogram[c] for c in box), i)
                      for i, box in enumerate(boxes) if len(box) > 1]
        if not candidates:
            break
        _, index = max(candidates)
        box = boxes.pop(index)
        axis = max(range(3), key=lambda k: max(c[k] for c in box) - min(c[k] for c in box))
        box.sort(key=lambda c: c[axis])
        total = sum(histogram[c] for c in box)
        accumulated = 0
        cut = 1
        for cut in range(1, len(box)):
            accumulated += histogram[box[cut - 1]]
            if accumulated * 2 >= total:
                break
        boxes.extend((box[:cut], box[cut:]))
    palette = [(0, 0, 0, 0)]
    for box in boxes:
        total = sum(histogram[c] for c in box)
        palette.append(expand(tuple(sum(c[k] * histogram[c] for c in box) // total
                                    for k in range(4))))
    return palette


def normalize():
    width, height, rgba = decode_png((ASSETS / '02-keeper-grid-edit.png').read_bytes())
    source = [tuple(rgba[i:i + 4]) for i in range(0, len(rgba), 4)]
    occupied = [(i % width, i // width) for i, p in enumerate(source) if p[3] >= 128]
    x0 = min(x for x, y in occupied)
    y0 = min(y for x, y in occupied)
    x1 = max(x for x, y in occupied) + 1
    y1 = max(y for x, y in occupied) + 1
    target_h = 38
    target_w = round((x1 - x0) * target_h / (y1 - y0))
    pixels = [(0, 0, 0, 0)] * (48 * 48)
    # Center-sample the enlarged AI pixel grid directly; never interpolate.
    for y in range(target_h):
        sy = y0 + (2 * y + 1) * (y1 - y0) // (2 * target_h)
        for x in range(target_w):
            sx = x0 + (2 * x + 1) * (x1 - x0) // (2 * target_w)
            p = source[sy * width + sx]
            pixels[(y + 5) * 48 + x + (48 - target_w) // 2] = (
                p[0], p[1], p[2], 255) if p[3] >= 128 else (0, 0, 0, 0)
    # Remove disconnected one-pixel alpha specks. Preserve all internal color clusters.
    original = pixels[:]
    for y in range(1, 47):
        for x in range(1, 47):
            i = y * 48 + x
            if original[i][3] and not any(original[i + d][3] for d in (-48, -1, 1, 48)):
                pixels[i] = (0, 0, 0, 0)
    # Add a one-pixel exterior outline without overwriting face or coat details.
    original = pixels[:]
    for y in range(1, 47):
        for x in range(1, 47):
            i = y * 48 + x
            if not original[i][3] and any(original[i + d][3] for d in (-48, -1, 1, 48)):
                pixels[i] = (8, 8, 33, 255)
    palette = palette_for(pixels, 32)
    mapped = []
    indices = bytearray()
    for p in pixels:
        index = (min(range(1, len(palette)),
                     key=lambda j: sum((p[k] - palette[j][k]) ** 2 for k in range(3)))
                 if p[3] else 0)
        indices.append(index)
        mapped.append(palette[index])
    png(ASSETS / '03-keeper-native.png', 48, 48, mapped)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    png(OUTPUT / 'art-sample-keeper-8x.png', 384, 384,
        [mapped[(y // 8) * 48 + x // 8] for y in range(384) for x in range(384)])
    (ASSETS / '03-palette.txt').write_text('\n'.join(
        f'{i:02d}: RGB565=0x{((p[0] >> 3) << 11 | (p[1] >> 2) << 5 | p[2] >> 3):04x}'
        f' A4={p[3] // 17}' for i, p in enumerate(palette)) + '\n')
    print(f'source={width}x{height}; alpha bounds=({x0},{y0})..({x1},{y1}); '
          f'native=48x48; figure={target_w}x38; palette={len(palette)}')


if __name__ == '__main__':
    normalize()
