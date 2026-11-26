#!/usr/bin/env python3
"""gpu-spec 2.6: CC0 PNGs / OFL BDF -> tiled I8 atlases and RGB565 mipmaps.
Only Python standard library; generated headers belong in build/.
"""
import math
import pathlib
import struct
import sys
import zlib

root = pathlib.Path(__file__).resolve().parents[2]
art = root / 'gpu_test2d/assets/kenney'
terrain = root / 'gpu_test3d/assets/kenney'
out = pathlib.Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
tex = bytearray(185792)
colors = [0xffff, 0xffff, 0x3fff, 0xfc9f, 0xfd29, 0x0434, 0xbadf, 0xffa5,
          0x0865, 0x1b12, 0x2298, 0x447d, 0x6d5f, 0x977f, 0x27e9, 0xf986]
palette = [0] + [0xf0000 | c for c in colors[1:]]
palette += [(i << 16) | 0xffff for i in range(16)]
for r in range(6):
    for g in range(6):
        for b in range(6):
            palette.append(0xf0000 | ((r*51 >> 3) << 11) | ((g*51 >> 2) << 5) | (b*51 >> 3))
palette += [0] * (256-len(palette))

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

def store(base, width, x, y, value, rgb=False):
    bx = x if rgb else x//2
    blocks = width if rgb else width//2
    addr = base+8*((y//2)*((blocks+1)//2)+bx//2)+2*((bx&1)+2*(y&1))
    if rgb: tex[addr:addr+2] = value.to_bytes(2, 'little')
    else: tex[addr+(x&1)] = value

def index(p):
    r,g,b,a = p
    return 0 if a < 96 else 32+round(r/51)*36+round(g/51)*6+round(b/51)

def sprite(name, x0, y0, w, h, base=0):
    image = resize(png(art/name), w, h)
    for y,row in enumerate(image):
        for x,p in enumerate(row): store(base, 256, x0+x, y0+y, index(p))

sprite('playerShip1_blue.png',32,0,32,32)
for i, name in enumerate(['enemyRed1.png','enemyRed3.png','enemyRed5.png']):
    sprite(name,64+i*32,0,32,32)
sprite('ufoRed.png',160,0,64,64)
sprite('wingRed_2.png',224,0,32,32)
for i in range(3): sprite(f'fire0{i}.png',16+i*16,32,16,24)
sprite('shield1.png',64,32,64,64)
sprite('laserBlue01.png',8,0,8,32)
for y in range(8):
    for x in range(16,32): store(0,256,x,y,16+x-16)
# Original homing missile: bright nose, body and two orange tail fins.
for y in range(16):
    for x in range(8):
        d = abs(x-3.5)
        c = 0
        if y < 5 and d < (y+1)/2: c = 1
        if 5 <= y < 13 and d < 2: c = 1 if x < 4 else 2
        if 10 <= y < 15 and d < 4-y%2: c = 4 if d > 1 else 1
        store(0,256,224+x,32+y,c)
sprite('planet03.png',0,0,96,96,65536)
sprite('meteorBrown_big1.png',128,128,32,32,65536)
sprite('powerupYellow_star.png',160,128,16,16,65536)
sprite('pill_green.png',176,128,16,16,65536)
# Hand-authored effects are generated in the same palette as the CC0 artwork.
for y in range(8):
    for x in range(8):
        a = max(0, 15-int(math.hypot(x-3.5,y-3.5)*3.7))
        store(0,256,x,y,16+a)
for y in range(16):
    for x in range(16):
        a = max(0,15-int(math.hypot(x-7.5,y-7.5)*1.9))
        store(0,256,x,y+32,16+a)
for frame in range(4):
    for y in range(32):
        for x in range(32):
            radius=math.hypot(x-15.5,y-15.5)
            boundary=6+frame*3+(math.sin(math.atan2(y-15.5,x-15.5)*9)*2)
            c=0
            if radius < boundary and radius > max(0,frame*4-4):
                c=1 if radius < boundary*.5 else 7 if radius < boundary*.8 else 4
            store(0,256,128+frame*32+x,64+y,c)
# Dark star field + transparent nebula and cloud shapes on secondary atlas.
for y in range(64):
    for x in range(64):
        store(0,256,x,64+y,1 if (x*73+y*151)%997 < 2 else 8)
for y in range(128):
    for x in range(128):
        wave=math.sin(x/22+math.sin(y/31)*2)+math.sin(y/18+x/45)
        c=index((51,0,102,255)) if wave>0 else index((0,51,102,255))
        store(65536,256,x+128,y,c if wave>-.7 else 0)
for y in range(64):
    for x in range(128):
        inside=any(((x-cx)/rx)**2+((y-cy)/ry)**2<1 for cx,cy,rx,ry in
                   [(28,40,27,13),(52,29,25,21),(80,34,28,17),(102,42,22,11)])
        store(65536,256,x,128+y,1 if inside else 0)
for y in range(248,256):
    for x in range(248,256): store(0,256,x,y,1)
# 12px Chinese subset; ASCII remains the BSP public-domain font.
bdf=(root/'gpu_test_common/assets/fusion-pixel/hud.bdf').read_text()
glyphs=[]
for block in bdf.split('STARTCHAR ')[1:]:
    cp=int(block.split('ENCODING ')[1].splitlines()[0])
    w,h,dx,dy=map(int,block.split('BBX ')[1].splitlines()[0].split())
    bitmap=block.split('BITMAP\n')[1].split('ENDCHAR')[0].splitlines()
    g=len(glyphs)
    glyphs.append(cp)
    for y,line in enumerate(bitmap):
        bits=int(line,16)
        for x in range(w):
            if bits & (1 << (len(line)*4-1-x)):
                store(0,256,128+(g%10)*12+x+dx,128+(g//10)*12+10-dy-h+y,1)
# Five 64x64, seven-level chains: grass, rock, sand, checker, aircraft/cystal skin.
images=[resize(png(terrain/name),64,64) for name in
        ['floor_ground_grass.png','wall_rock.png','floor_ground_sand.png']]
images.append([[(255,204,102,255) if ((x//8)^(y//8))&1 else (0,153,204,255)
                for x in range(64)] for y in range(64)])
blue = resize(png(art/'playerShip1_blue.png'),32,64)
red = resize(png(art/'enemyRed1.png'),32,64)
images.append([blue[y]+red[y] for y in range(64)])
for t,image in enumerate(images):
    base=131072+t*10944
    for level in range(7):
        w=len(image)
        for y,row in enumerate(image):
            for x,(r,g,b,a) in enumerate(row):
                if t==4 and a<96: r,g,b=24,66,102
                # Keep the canyon saturated and readable under vertex lighting.
                if t==0: r,g,b=r*3//5,min(255,g*6//5+45),b*3//5
                if t==1: r,g,b=min(255,r+48),g*4//5,b*3//4
                color=((r>>3)<<11)|((g>>2)<<5)|(b>>3)
                store(base,w,x,y,color,True)
        base+=8*((w+1)//2)*((w+1)//2)
        if w>1:
            image=[[tuple(sum(image[y*2+j][x*2+i][c] for i in range(2)
                             for j in range(2))//4 for c in range(4))
                    for x in range(w//2)] for y in range(w//2)]
with out.open('w') as f:
    f.write('/* assets.h — gpu-spec 2.6; generated from CC0/OFL sources. */\n')
    f.write('static const unsigned char test_asset_texture[185792] = {\n')
    for i in range(0,len(tex),32): f.write(','.join(map(str,tex[i:i+32]))+',\n')
    f.write('};\nstatic const uint32_t test_asset_palette[256] = {\n')
    f.write(','.join(map(str,palette))+'};\n')
    f.write('static const unsigned test_chinese[] = {'+','.join(map(str,glyphs))+'};\n')
    f.write('const int16_t test_sine[256] = {\n')
    f.write(','.join(str(round(math.sin(i*math.tau/256)*16384)) for i in range(256)))
    f.write('};\n')
