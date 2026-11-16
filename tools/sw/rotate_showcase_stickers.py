#!/usr/bin/env python3
"""rotate_showcase_stickers.py — T-FACE-STICKER-R2 offline angle frames.

Standard-library PNG rotation; 160 px artwork centered on a 220 px canvas.
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
        for angle, suffix in [(-24, 'm24'), (-12, 'm12'), (0, 'z0'),
                              (12, 'p12'), (24, 'p24')]:
            c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
            pixels = bytearray(220*220*4)
            for y in range(220):
                for x in range(220):
                    dx, dy = x-109.5, y-109.5
                    sx = round(c*dx+s*dy+(w-1)/2)
                    sy = round(-s*dx+c*dy+(h-1)/2)
                    if 0 <= sx < w and 0 <= sy < h:
                        a, b = (y*220+x)*4, (sy*w+sx)*4
                        pixels[a:a+4] = rgba[b:b+4]
            write_png(output / f'{path.stem}_{suffix}.png', 220, 220, pixels)
            total += len(pixels)
    print(f'sticker ARGB8888 bytes: {total}')


if __name__ == '__main__':
    main()
