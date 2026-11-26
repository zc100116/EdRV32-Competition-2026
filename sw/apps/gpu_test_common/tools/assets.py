#!/usr/bin/env python3
"""gpu-spec 2.6: project-owned imagegen art / OFL BDF -> 192 KiB GPU textures.
Shared palette and processing live in art.py; generated output belongs in build/.
"""
import math
import pathlib
import sys
from art import PALETTE, area_resize, cell, crop, nearest, png, process, write_png

root = pathlib.Path(__file__).resolve().parents[2]
art = root/'gpu_test2d/assets/imagegen'
terrain = root/'gpu_test3d/assets/imagegen'
out = pathlib.Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
tex = bytearray(185792)
colors = [0xffff,0xffff,0x3fff,0xfb8f,0xfd29,0x0434,0xbb5f,0xffa5,
          0x1085,0x6292,0x52f7,0x6379,0x7c1c,0x949d,0xad5f,0xf986]
palette = [0]+[0xf0000|c for c in colors[1:]]
palette += [(i<<16)|0xffff for i in range(16)]
palette += [0xf0000|((r>>3)<<11)|((g>>2)<<5)|(b>>3) for r,g,b in PALETTE]
palette += [0]*(256-len(palette))
atlases = [[[(0,0,0,0)]*256 for _ in range(256)] for _ in range(2)]

def store(base, width, x, y, value, rgb=False):
    bx = x if rgb else x//2
    blocks = width if rgb else width//2
    addr = base+8*((y//2)*((blocks+1)//2)+bx//2)+2*((bx&1)+2*(y&1))
    if rgb: tex[addr:addr+2] = value.to_bytes(2,'little')
    else: tex[addr+(x&1)] = value

def index(p):
    return 0 if p[3] < 96 else 32+nearest(p[:3])

def place(image, x0, y0, w, h, atlas=0, outline=True, trim=True, glow=False):
    image = process(image, w, h, outline=outline, trim=trim)
    for y,row in enumerate(image):
        for x,p in enumerate(row):
            if glow:
                strength = (max(p[:3])+min(p[:3]))*p[3]//510
                value = 16+round(strength*15/255) if strength else 0
            else: value = index(p)
            store(atlas*65536,256,x0+x,y0+y,value)
            atlases[atlas][y0+y][x0+x] = p

ships = png(art/'ships-effects.png')
place(cell(ships,0,0,4,4),32,0,32,32)
for i in range(3): place(cell(ships,i+1,0,4,4),64+i*32,0,32,32)
# The generated boss extends slightly beyond its nominal first quarter cell.
place(crop(ships,0,len(ships)//4,len(ships[0])*28//100,len(ships)//4),0,0,128,96,1)
place(cell(ships,1,1,4,4),224,0,32,32)
for i in range(4): place(cell(ships,i,2,4,4),16+i*12,32,12,24,outline=False)
place(cell(ships,2,1,4,4),64,32,64,64,outline=False,glow=True)
# A shield is a rim, so its central opening stays transparent over the player.
for y in range(64):
    for x in range(64):
        if (x-31.5)**2+(y-31.5)**2 < 23**2: store(0,256,64+x,32+y,0)
place(cell(ships,3,1,4,4),224,0,32,32,1)
for i in range(2): place(cell(ships,i,3,4,4),128+i*16,96,16,16,1)
place(cell(ships,2,3,4,4),0,0,8,8,outline=False,glow=True)
place(cell(ships,2,3,4,4),0,32,16,16,outline=False,glow=True)
# The 3D glow is enlarged in perspective: radial alpha removes the source's
# square pixel core, while retaining the generated sprite's silhouette/alpha.
for y in range(16):
    for x in range(16):
        radius = math.hypot(x-7.5,y-7.5)/7.5
        strength = round(max(0,1-radius)**1.4*15)
        alpha = atlases[0][32+y][x][3]
        strength = strength*alpha//255
        store(0,256,x,32+y,16+strength if strength else 0)
place(cell(ships,3,3,4,4),8,0,8,32,outline=False,glow=True)
# Missile uses the generated golden interceptor with an elongated silhouette.
place(cell(ships,3,0,4,4)[::-1],224,32,8,16)
for y in range(8):
    for x in range(16,32): store(0,256,x,y,16+x-16)
explosions = png(art/'explosion.png')
for frame in range(8):
    place(cell(explosions,frame%4,frame//4,4,2),128+frame%4*32,64+frame//4*32,
          32,32,outline=False,trim=False)
environment = png(art/'environment-ui.png')
place(cell(environment,0,0,2,2),0,128,256,128,1,outline=False,trim=False)
# Stretch the nebula to the full background atlas region, with no letterboxing.
nebula = area_resize(cell(environment,0,0,2,2),256,128)
for y,row in enumerate(nebula):
    for x,p in enumerate(row): store(65536,256,x,128+y,index((*p[:3],255)))
place(cell(environment,1,0,2,2),128,0,96,96,1,outline=False)
place(cell(environment,0,1,2,2),160,96,96,32,1,outline=False)
# Source panel crop: top 2/3 of its atlas quarter; reusable 32x16 nine-slice.
ui = cell(environment,1,1,2,2)
place(crop(ui,0,0,len(ui[0]),len(ui)*2//3),0,96,32,16,outline=False)
# Four generated HUD icons from the bottom portion of that quarter.
for i in range(4):
    place(crop(ui,i*len(ui[0])//4,len(ui)*3//5,len(ui[0])//4,len(ui)*2//5),
          32+i*12,112,12,12)
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

materials = png(terrain/'materials.png')
# Sand, canyon rock, purple side rock, checker, and shared aircraft/drone skin.
images = [area_resize(cell(materials,0,0,2,2),64,64),
          area_resize(cell(materials,1,0,2,2),64,64),
          area_resize(cell(materials,0,1,2,2),64,64)]
images.append([[(*PALETTE[43 if ((x//8)^(y//8))&1 else 11],255)
                for x in range(64)] for y in range(64)])
images.append(area_resize(cell(materials,1,1,2,2),64,64))
# Mesh UVs keep crystal/ship color accents; side rocks use the purple mineral chain.
for t,image in enumerate(images):
    images[t] = [[(*PALETTE[nearest(p[:3])],255) for p in row] for row in image]
    write_png(out.parent/f'material-{t}.png',images[t])
for i,atlas in enumerate(atlases): write_png(out.parent/f'atlas-{i}.png',atlas)
for t,image in enumerate(images):
    base=131072+t*10944
    for level in range(7):
        w=len(image)
        for y,row in enumerate(image):
            for x,(r,g,b,a) in enumerate(row):
                color=((r>>3)<<11)|((g>>2)<<5)|(b>>3)
                store(base,w,x,y,color,True)
        base+=8*((w+1)//2)*((w+1)//2)
        if w>1:
            image=[[tuple(sum(image[y*2+j][x*2+i][c] for i in range(2)
                             for j in range(2))//4 for c in range(4))
                    for x in range(w//2)] for y in range(w//2)]
with out.open('w') as f:
    f.write('/* assets.h — gpu-spec 2.6; generated from project-owned imagegen / OFL sources. */\n')
    f.write('static const unsigned char test_asset_texture[185792] = {\n')
    for i in range(0,len(tex),32): f.write(','.join(map(str,tex[i:i+32]))+',\n')
    f.write('};\nstatic const uint32_t test_asset_palette[256] = {\n')
    f.write(','.join(map(str,palette))+'};\n')
    f.write('static const unsigned test_chinese[] = {'+','.join(map(str,glyphs))+'};\n')
    f.write('const int16_t test_sine[256] = {\n')
    f.write(','.join(str(round(math.sin(i*math.tau/256)*16384)) for i in range(256)))
    f.write('};\n')
