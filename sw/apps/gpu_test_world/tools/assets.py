#!/usr/bin/env python3
"""G-4: original imagegen island materials -> RGB565 seven-level mip chains."""
import math
import pathlib
import sys
app=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(app.parents[2]/'sw/apps/gpu_test_common/tools'))
from art import png, cell, process
image=png(app/'assets/terrain-v2.png')
result=bytearray(5*10944)
for t in range(5):
    material=process(cell(image,t%2,(t//2)%2,2,2),64,64,outline=False,trim=False)
    if t==4:
        # Neutral pixel skin modulates the mesh's teal, white, copper and rock colours.
        material=[[(v,v,v,255) for p in row for v in [205+(sum(p[:3])//3)%50]] for row in material]
    base=t*10944
    for level in range(7):
        w=len(material)
        for y,row in enumerate(material):
            for x,(r,g,b,a) in enumerate(row):
                color=((r>>3)<<11)|((g>>2)<<5)|(b>>3)
                address=base+8*((y//2)*((w+1)//2)+x//2)+2*((x&1)+2*(y&1))
                result[address:address+2]=color.to_bytes(2,'little')
        base+=8*((w+1)//2)**2
        if w>1:
            material=[[tuple(sum(material[2*y+j][2*x+i][c] for i in range(2)
                       for j in range(2))//4 for c in range(4))for x in range(w//2)]for y in range(w//2)]
out=pathlib.Path(sys.argv[1]);out.parent.mkdir(parents=True,exist_ok=True)
with out.open('w') as f:
    f.write('/* world_assets.h — G-4, gpu-spec 2.6; generated island mip chains. */\n')
    f.write('static const unsigned char world_materials[54720] = {\n')
    for i in range(0,len(result),32):f.write(','.join(map(str,result[i:i+32]))+',\n')
    f.write('};\n')

# Scene I8 atlas: radial light, quiet translucent water, shoreline foam, soft clouds.
effects=bytearray(65536)
def put(x,y,value):
    bx=x//2
    address=8*((y//2)*64+bx//2)+2*((bx&1)+2*(y&1))+(x&1)
    effects[address]=value
for y in range(32):
    for x in range(32):
        r=math.hypot(x-15.5,y-15.5)/15.5
        value=round(15*max(0,1-r)**1.4)
        put(16+x,96+y,16+value if value else 0)
for y in range(16):
    for x in range(32):
        wave=abs(y-7-2*math.sin(x/6))
        put(192+x,96+y,16+max(0,10-round(wave*3)) if wave<3 else 0)
for y in range(8):
    for x in range(8):
        put(240+x,96+y,105)
        put(232+x,96+y,106)
for y in range(32):
    for x in range(96):
        strength=max(max(0,1-((x-cx)/rx)**2-((y-cy)/ry)**2)
                     for cx,cy,rx,ry in [(25,19,25,10),(44,13,22,12),(67,19,27,9)])
        a=round(strength*7)
        put(x,160+y,16+a if a else 0)
with out.open('a') as f:
    f.write('static const unsigned char world_effects[65536] = {\n')
    for i in range(0,len(effects),32):f.write(','.join(map(str,effects[i:i+32]))+',\n')
    f.write('};\n')
