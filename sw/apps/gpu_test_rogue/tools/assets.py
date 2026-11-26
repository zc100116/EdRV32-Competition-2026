#!/usr/bin/env python3
"""G-4: imagegen sprites and original tiles -> GPU I8 block-interleaved source data."""
import math
import pathlib
import sys

app = pathlib.Path(__file__).resolve().parents[1]
root = app.parents[2]
out = pathlib.Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
sys.path.insert(0,str(root/'sw/apps/gpu_test_common/tools'))
from art import png, process, nearest, cell, area_resize
def index(p):
    return 0 if p[3]<96 else 32+nearest(p[:3])
primary, tiles = bytearray(32768), bytearray(65536)
def put(buf, x, y, c):
    bx = x//2
    address = 8*((y//2)*64+bx//2)+2*((bx&1)+2*(y&1))+(x&1)
    buf[address] = c
image = png(app/'assets/actors.png')
h,w = len(image),len(image[0])
for slot in range(8):
    x,y = (slot%4)*w//4,(slot//4)*h//2
    sprite = [row[x:x+w//4] for row in image[y:y+h//2]]
    size = 32 if slot < 4 else 64 if slot < 6 else 48
    sprite = process(sprite,size,size)
    for yy,row in enumerate(sprite):
        for xx,p in enumerate(row): put(primary,(slot%4)*64+xx,(slot//4)*64+yy+(32 if slot==0 else 0),index(p))
# New-scene panel corners occupy an unused cell gap, away from the Boss sprite.
for y in range(16):
    for x in range(32):
        edge=min(x,31-x,y,15-y)
        put(primary,224+x,32+y,2 if edge==1 else 9 if edge==0 else 0)
# imagegen mechanical tiles: native 16px floors and 32px wall faces.
dungeon = png(app/'assets/dungeon.png')
for t in range(7):
    tile = area_resize(cell(dungeon,t%4,t//4,4,2),16 if t<3 else 32,16 if t<3 else 32)
    ox,oy = (t*16,0) if t<3 else ((t-3)*32,32)
    for y,row in enumerate(tile):
        for x,p in enumerate(row):put(tiles,ox+x,oy+y,index(p))
# Fourth floor variation is a plain worn section of the etched plate.
plate=area_resize(cell(dungeon,0,0,4,2),1,1)[0][0]
for y in range(16):
    for x in range(16):
        # Broad plate, seam, lit bevel and two small scuffs from the source swatch.
        shade=-18 if x==0 or y==0 else 8 if x==1 or y==1 else 0
        if (x,y) in [(11,5),(12,5),(6,12)]:shade+=7
        rgb=tuple(max(0,min(255,plate[c]+shade)) for c in range(3))
        put(tiles,48+x,y,index((*rgb,255)))
for y in range(24):
    for x in range(24):put(tiles,160+x,y,8)
flames = cell(dungeon,3,1,4,2)
for f in range(4):
    source = cell(flames,f,0,4,1)
    # Remove the source navy backdrop before the normal effect processing.
    source = [[(*p[:3],255 if p[1]>85 and p[1]>p[0]*1.6 else 0) for p in row]
              for row in source]
    fire = process(source,16,24,outline=False)
    for y,row in enumerate(fire):
        for x,p in enumerate(row):put(tiles,128+f*16+x,32+y,index(p))
# Shadow ellipse: palette index 104 is reserved for a translucent navy sample.
for y in range(12):
    for x in range(32):
        put(tiles,80+x,96+y,104 if ((x-15.5)/16)**2+((y-5.5)/6)**2<1 else 0)
# Crescent gradient strip: transparent at both radial edges, bright at the blade.
for y in range(16):
    for x in range(32):
        strength=round(15*(1-x/32)**0.6*max(0,1-abs(y-7.5)/8)**0.8)
        put(tiles,128+x,96+y,16+strength if strength else 0)
# Amber/coral faceted debris, distinct from the glowing sparks.
for y in range(8):
    for x in range(8):
        put(tiles,112+x,96+y,0 if abs(x-3)+abs(y-3)>4 else 4 if x+y<6 else 3)
for y in range(32):
    for x in range(32):
        radius=((x-15.5)**2+(y-15.5)**2)**.5
        put(tiles,16+x,96+y,16+max(0,15-int(radius)))
for y in range(8):
    for x in range(8):
        a=max(0,15-int(((x-3.5)**2+(y-3.5)**2)**.5*4))
        put(tiles,x,96+y,16+a)
for y in range(12):
    for x in range(12):
        d=(x-5.5)**2+(y-5.5)**2
        put(tiles,64+x,96+y,0 if d>32 else 7 if d<19 else 4)
# White samples occupy the vacated hero cell; the hero now starts at (0,32).
for y in range(4):
    for x in range(4):put(primary,x,y,1)
bdf=(app/'assets/hud.bdf').read_text()
glyphs,bitmaps=[],[]
for block in bdf.split('STARTCHAR ')[1:]:
    cp=int(block.split('ENCODING ')[1].splitlines()[0])
    w,h,dx,dy=map(int,block.split('BBX ')[1].splitlines()[0].split())
    data=bytearray(144)
    for y,line in enumerate(block.split('BITMAP\n')[1].split('ENDCHAR')[0].splitlines()):
        bits=int(line,16)
        for x in range(w):
            if bits & (1<<(len(line)*4-1-x)):data[(y+10-dy-h)*12+x+dx]=1
    glyphs.append(cp);bitmaps.extend(data)
with out.open('w') as f:
    f.write('/* rogue_assets.h — G-4, gpu-spec 2.6; generated I8 source data. */\n')
    for name,data in [('rogue_primary',primary),('rogue_tiles',tiles),('demo_glyphs',bitmaps)]:
        f.write(f'static const unsigned char {name}[{len(data)}] = {{\n')
        for i in range(0,len(data),32):f.write(','.join(map(str,data[i:i+32]))+',\n')
        f.write('};\n')
    f.write('static const unsigned demo_chinese[] = {'+','.join(map(str,glyphs))+'};\n')

(out.parent/'sine.inc').write_text(','.join(str(round(math.sin(i*math.tau/256)*16384)) for i in range(256)))
