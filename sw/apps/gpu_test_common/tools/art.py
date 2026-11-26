#!/usr/bin/env python3
"""Shared cartoon-pixel art processing: PNG, area resize, palette, 1px outline.
Only Python standard library. The CLI writes one processed sprite; assets.py uses
these same functions for the atlases. PNG CRCs are part of the file format only.
"""
import argparse
import json
import pathlib
import struct
import zlib

PALETTE = [tuple(bytes.fromhex(c)) for c in json.loads(
    (pathlib.Path(__file__).resolve().parents[1]/'assets/palette.json').read_text())]

def png(path):
    data = path.read_bytes()
    pos, packed, pal, alpha = 8, bytearray(), [], []
    while pos < len(data):
        n = int.from_bytes(data[pos:pos+4], 'big')
        tag, chunk = data[pos+4:pos+8], data[pos+8:pos+8+n]
        if tag == b'IHDR':
            w, h, depth, kind, _, _, interlace = struct.unpack('>IIBBBBB', chunk)
            if depth != 8 or interlace:
                raise ValueError(f'{path}: requires non-interlaced 8-bit PNG')
        elif tag == b'IDAT': packed.extend(chunk)
        elif tag == b'PLTE': pal = [tuple(chunk[i:i+3]) for i in range(0, n, 3)]
        elif tag == b'tRNS': alpha = list(chunk)
        pos += n+12
    channels = {2: 3, 3: 1, 6: 4}[kind]
    raw = zlib.decompress(packed)
    rows, prev, pos = [], bytearray(w*channels), 0
    for _ in range(h):
        filt = raw[pos]
        pos += 1
        row = bytearray(raw[pos:pos+w*channels])
        pos += w*channels
        for i in range(len(row)):
            a = row[i-channels] if i >= channels else 0
            b = prev[i]
            c = prev[i-channels] if i >= channels else 0
            if filt == 1: predict = a
            elif filt == 2: predict = b
            elif filt == 3: predict = (a+b)//2
            elif filt == 4:
                p = a+b-c
                distances = [abs(p-a), abs(p-b), abs(p-c)]
                predict = [a,b,c][distances.index(min(distances))]
            elif filt == 0: predict = 0
            else: raise ValueError(f'{path}: PNG filter {filt}')
            row[i] = (row[i]+predict)&255
        pixels = []
        for i in range(w):
            p = tuple(row[i*channels:(i+1)*channels])
            if kind == 3:
                pixels.append((*pal[p[0]], alpha[p[0]] if p[0] < len(alpha) else 255))
            else: pixels.append(p if kind == 6 else (*p, 255))
        rows.append(pixels)
        prev = row
    return rows

def resize(image, w, h):
    return [[image[y*len(image)//h][x*len(image[0])//w] for x in range(w)] for y in range(h)]


def write_png(path, image):
    h, w = len(image), len(image[0])
    def chunk(tag, data):
        return (struct.pack('>I', len(data))+tag+data+
                struct.pack('>I', zlib.crc32(tag+data)))
    raw = b''.join(b'\0'+bytes(c for p in row for c in p) for row in image)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+
                     chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))+
                     chunk(b'IDAT', zlib.compress(raw, 9))+chunk(b'IEND', b''))

def crop(image, x, y, w, h):
    return [row[x:x+w] for row in image[y:y+h]]

def cell(image, column, row, columns, rows):
    w, h = len(image[0])//columns, len(image)//rows
    return crop(image, column*w, row*h, w, h)

def area_resize(image, w, h):
    src_h, src_w = len(image), len(image[0])
    result = []
    for y in range(h):
        row = []
        for x in range(w):
            pixels = [image[sy][sx]
                      for sy in range(y*src_h//h, max(y*src_h//h+1, (y+1)*src_h//h))
                      for sx in range(x*src_w//w, max(x*src_w//w+1, (x+1)*src_w//w))]
            alpha = sum(p[3] for p in pixels)
            rgb = [sum(p[c]*p[3] for p in pixels)//alpha if alpha else 0 for c in range(3)]
            row.append((*rgb, alpha//len(pixels)))
        result.append(row)
    return result

def nearest(rgb):
    return min(range(len(PALETTE)), key=lambda i:
               sum((rgb[c]-PALETTE[i][c])**2 for c in range(3)))

def process(image, w, h, outline=True, trim=True):
    if trim:
        positions = [(x,y) for y,row in enumerate(image)
                     for x,p in enumerate(row) if p[3] >= 128]
        x0 = min(x for x,y in positions)
        y0 = min(y for x,y in positions)
        x1 = max(x for x,y in positions)+1
        y1 = max(y for x,y in positions)+1
        image = crop(image, x0, y0, x1-x0, y1-y0)
    margin = 1 if outline else 0
    scale = min((w-margin*2)/len(image[0]), (h-margin*2)/len(image))
    iw, ih = max(1, round(len(image[0])*scale)), max(1, round(len(image)*scale))
    small = area_resize(image, iw, ih)
    result = [[(0,0,0,0)]*w for _ in range(h)]
    ox, oy = (w-iw)//2, (h-ih)//2
    for y,row in enumerate(small):
        for x,p in enumerate(row):
            if p[3] >= (128 if outline else 8):
                alpha = 255 if outline else round(p[3]/17)*17
                result[oy+y][ox+x] = (*PALETTE[nearest(p[:3])], alpha)
    if outline:
        solid = [[p[3] != 0 for p in row] for row in result]
        for y in range(h):
            for x in range(w):
                neighbors = [(nx,ny) for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1))
                             if 0 <= nx < w and 0 <= ny < h]
                count = sum(solid[ny][nx] for nx,ny in neighbors)
                if not solid[y][x] and count: result[y][x] = (*PALETTE[0],255)
                elif solid[y][x] and not count: result[y][x] = (0,0,0,0)
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    parser.add_argument('--effect', action='store_true', help='preserve alpha; no outline')
    args = parser.parse_args()
    write_png(args.output, process(png(args.input), args.width, args.height,
                                  outline=not args.effect))
