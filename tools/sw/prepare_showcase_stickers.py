#!/usr/bin/env python3
"""prepare_showcase_stickers.py — T-FACE-STICKER-R2 alpha crop and bilinear resize.
Generated transparent artwork becomes 160-square RGBA8 noninterlaced PNG; host only.
"""
import sys
from pathlib import Path
from png2c import decode_png
from rotate_showcase_stickers import write_png


def main():
    source, output = map(Path, sys.argv[1:])
    output.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.glob('*.png')):
        width, height, pixels = decode_png(path.read_bytes())
        coords = [(i % width, i // width) for i in range(width*height)
                  if pixels[i*4+3] > 32]
        x0 = min(x for x, y in coords)
        x1 = max(x for x, y in coords)+1
        y0 = min(y for x, y in coords)
        y1 = max(y for x, y in coords)+1
        ratio = 156/max(x1-x0, y1-y0)
        new_width = round((x1-x0)*ratio)
        new_height = round((y1-y0)*ratio)
        result = bytearray(160*160*4)
        for y in range(new_height):
            for x in range(new_width):
                sx = x0+(x+.5)/ratio-.5
                sy = y0+(y+.5)/ratio-.5
                ix, iy = int(sx), int(sy)
                fx, fy = sx-ix, sy-iy
                pos = ((y+(160-new_height)//2)*160+x+(160-new_width)//2)*4
                for channel in range(4):
                    result[pos+channel] = round(sum(
                        pixels[((iy+dy)*width+ix+dx)*4+channel]*a*b
                        for dx, a in [(0, 1-fx), (1, fx)]
                        for dy, b in [(0, 1-fy), (1, fy)]))
        write_png(output/path.name, 160, 160, result)
        print(path.name, width, height, '->160x160')


if __name__ == '__main__':
    main()
