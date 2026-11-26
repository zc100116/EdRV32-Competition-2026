#!/usr/bin/env python3
"""gpu-spec 2.6: original indexed atlas, terrain mip chain and Q14 sine table."""
import math
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
tex = bytearray(76480)

def store(base, width, x, y, value, rgb=False):
    bx = x if rgb else x // 2
    blocks = width if rgb else width // 2
    addr = base + 8 * ((y // 2) * ((blocks + 1) // 2) + bx // 2)
    addr += 2 * ((bx & 1) + 2 * (y & 1))
    if rgb:
        tex[addr:addr+2] = value.to_bytes(2, 'little')
    else:
        tex[addr + (x & 1)] = value

for y in range(128):
    for x in range(256):
        c = 0
        if x < 8 and y < 8:
            d = (x-3)**2 + (y-3)**2
            c = 1 if d < 4 else 3 if d < 11 else 0
        if 32 <= x < 64 and y < 32:
            a, b = x-48, y-16
            if abs(a) <= (b+16)//2 and b < 12:
                c = 1 if abs(a) < 3 else 2 if b < 2 else 5
            if abs(a) < 5 and 11 <= b < 16:
                c = 4
        if 64 <= x < 96 and y < 32:
            a, b = x-80, y-16
            if abs(a)+abs(b)*2 < 22:
                c = 6 if b < 0 else 4
            if abs(a) < 4 and abs(b) < 4:
                c = 1
        if 96 <= x < 160 and y < 64:
            a, b = x-128, y-32
            if a*a*2+b*b < 850:
                c = 6 if b < -8 else 4 if abs(a) > 14 else 5
            if a*a+b*b < 110:
                c = 1 if a*a+b*b < 45 else 2
        if x < 16 and 32 <= y < 48:
            d = (x-7)**2+(y-39)**2
            c = 1 if d < 8 else 4 if d < 24 else 7 if d < 52 else 0
        if x < 64 and 64 <= y < 128:
            a, b = x, y-64
            c = 9 if (a*73+b*151)%499 < 4 else 8
        store(0, 256, x, y, c)
for y in range(248, 256):
    for x in range(248, 256):
        store(0, 256, x, y, 1)
base = 65536
for level in range(7):
    w = max(1, 64 >> level)
    for y in range(w):
        for x in range(w):
            if level <= 3:
                checker = ((x >> (3-level)) ^ (y >> (3-level))) & 1
                c = 0xff9a if checker else 0x2d7b
            else:
                c = 0x96ba
            store(base, w, x, y, c, True)
    base += 8*((w+1)//2)*((w+1)//2)
with out.open('w') as f:
    f.write('/* assets.h — gpu-spec 2.6; generated original procedural atlas. */\n')
    f.write('static const unsigned char test_asset_texture[76480] = {\n')
    for i in range(0, len(tex), 32):
        f.write(','.join(map(str, tex[i:i+32]))+',\n')
    f.write('};\nconst int16_t test_sine[256] = {\n')
    f.write(','.join(str(round(math.sin(i*math.tau/256)*16384)) for i in range(256)))
    f.write('};\n')
