#!/usr/bin/env python3
"""G-4: original imagegen island materials -> RGB565 seven-level mip chains."""
import pathlib
import sys
app=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(app.parents[2]/'sw/apps/gpu_test_common/tools'))
from art import png, cell, process
image=png(app/'assets/terrain.png')
result=bytearray(4*10944)
for t in range(4):
    material=process(cell(image,t%2,t//2,2,2),64,64,outline=False,trim=False)
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
    f.write('static const unsigned char world_materials[43776] = {\n')
    for i in range(0,len(result),32):f.write(','.join(map(str,result[i:i+32]))+',\n')
    f.write('};\n')
