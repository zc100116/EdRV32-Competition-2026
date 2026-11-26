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
from art import png, process, nearest
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
    cell = [row[x:x+w//4] for row in image[y:y+h//2]]
    size = 32 if slot < 4 else 64 if slot < 6 else 48
    cell = process(cell,size,size)
    for yy,row in enumerate(cell):
        for xx,p in enumerate(row): put(primary,(slot%4)*64+xx,(slot//4)*64+yy,index(p))
# New-scene panel corners occupy an unused cell gap, away from the Boss sprite.
for y in range(16):
    for x in range(32):
        edge=min(x,31-x,y,15-y)
        put(primary,224+x,32+y,2 if edge==1 else 9 if edge==0 else 0)
# Native floor/wall/door palette tiles: dark large clusters, two edge shades.
colors = [(35,40,77),(42,49,88),(49,58,99),(82,76,117),(126,68,57),(12,20,39)]
for t,(r,g,b) in enumerate(colors):
    for y in range(32):
        for x in range(32):
            k = -18 if x<2 or y<2 else 15 if x==3 or y==3 else 0
            if t<3 and ((x//8*13+y//8*7+t)%19==0): k-=8
            put(tiles,t*32+x,y,index((max(0,r+k),max(0,g+k),max(0,b+k),255)))
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
# Index 1 is reserved for solid white samples and palette tinting.
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
