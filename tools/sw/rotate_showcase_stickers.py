#!/usr/bin/env python3
"""rotate_showcase_stickers.py — T-FACE-STICKER-R2 offline angle frames.

Standard-library PNG rotation; artwork centered on an 11/8-width canvas.
Positive angles turn clockwise in display coordinates. Host build domain.
"""
import math
from pathlib import Path
import struct
import sys
import zlib
from png2c import decode_png


def write_png(path, width, height, rgba):
    def chunk(kind, data):
        return (struct.pack('>I', len(data)) + kind + data +
                struct.pack('>I', zlib.crc32(kind + data)))
    raw = b''.join(b'\0' + rgba[y*width*4:(y+1)*width*4] for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' +
                     chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def main():
    source, output = map(Path, sys.argv[1:])
    output.mkdir(parents=True, exist_ok=True)
    total = 0
    for path in sorted(source.glob('*.png')):
        w, h, rgba = decode_png(path.read_bytes())
        variants = [(path.stem, rgba)]
        if path.stem == 'cat-whiskers':
            mirrored = bytearray(len(rgba))
            for y in range(h):
                for x in range(w):
                    dest, src = (y*w+x)*4, (y*w+w-1-x)*4
                    mirrored[dest:dest+4] = rgba[src:src+4]
            variants.append(('cat-whiskers-left', mirrored))
        for name, rgba in variants:
            canvas = w*11//8
            for angle, suffix in [(-24, 'm24'), (-12, 'm12'), (0, 'z0'),
                                  (12, 'p12'), (24, 'p24')]:
                c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
                pixels = bytearray(canvas*canvas*4)
                for y in range(canvas):
                    for x in range(canvas):
                        dx, dy = x-(canvas-1)/2, y-(canvas-1)/2
                        sx = round(c*dx+s*dy+(w-1)/2)
                        sy = round(-s*dx+c*dy+(h-1)/2)
                        if 0 <= sx < w and 0 <= sy < h:
                            a, b = (y*canvas+x)*4, (sy*w+sx)*4
                            pixels[a:a+4] = rgba[b:b+4]
                write_png(output / f'{name}_{suffix}.png', canvas, canvas, pixels)
                total += len(pixels)
    print(f'sticker ARGB8888 bytes: {total}')


if __name__ == '__main__':
    main()
