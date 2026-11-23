"""stress.py — gpu-spec 7: two 640x180 stripes of a 640x360 frame.
Host scene generator, no clock domain. I8 bilinear descriptor; quads remain nearest.
"""
from tools.gpu.scene import Scene
from scene_support import Case


def scene():
    c = Case()
    c.ready(SC_X1=640, SC_Y1=180, VP_W=640, VP_H=360)
    s = c.scene
    palette = s.records('PAL_ENTRY', [dict(RGB565=(i*4097)&65535,A4=15) for i in range(256)])
    source, size = s.texture([[i%256 for i in range(16*16)]],1,16,16)
    s.command('PAL_LOAD',SRC=palette,GROUP=0,ENTRIES=256)
    s.command('TEX_LOAD',SRC=source,DST=0,BYTES=size)
    s.command('SET_TEX',LOG2_W=4,LOG2_H=4,FORMAT=1,LEVELS=1,SAMPLE=1)
    # Exact integer pixel-space vertices map through this MVP to a 640x360 viewport.
    c.matrix([1/320,0,0,-1, 0,-1/180,0,1, 0,0,0,.5, 0,0,0,1])
    surface = s.reserve(640*360*2,4096)
    s.reg('OBJ_LIVE_RECT0',0)
    s.reg('OBJ_LIVE_RECT1',640 | (360<<16))
    for y0 in (0,180):
        c.target(TGT_Y0=y0,SC_X1=640,SC_Y0=y0,SC_Y1=y0+180,VP_W=640,VP_H=360)
        c.clear()
        quads = s.records('QUAD',[dict(X=(i*37)%624,Y=y0+(i*17)%164,W=16,H=16,
                                     ALPHA=191,DEPTH=200) for i in range(1000)])
        s.command('DRAW_QUAD',ADDR=quads,COUNT=1000)
        vertices = []
        for i in range(500):
            x,y = (i*41)%620,y0+(i*23)%160
            for dx,dy,u,v in [(0,0,0,0),(20,0,4096,0),(0,20,0,4096)]:
                vertices.append(dict(X=x+dx,Y=y+dy,Z=1,NZ=127,U=u,V=v,COLOR=65535))
        triangles = s.records('VERTEX',vertices)
        s.command('DRAW_TRI',ADDR=triangles,COUNT=500)
        objects = s.records('OBJ',[dict(ALIVE=1,PX=((i*31)%620)*256,
                                      PY=(y0+(i*13)%160)*256,VX=127,VY=63,
                                      AX=-17,AY=31,LIFE=120,W=4,H=4,ALPHA=255)
                                   for i in range(2000)])
        s.command('OBJ_STEP',ADDR=objects,COUNT=2000,STEP=1,DRAW=0)
        s.command('RESOLVE',BASE=surface,STRIDE=1280,X0=0,Y0=y0,X1=640,Y1=y0+180)
    return s
