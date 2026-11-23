"""GT-15: gpu-spec 2.1; two/eight stripes equal a full-frame reference via RESOLVE."""
from tools.gpu.model import GPU
from tools.gpu.scene import Memory
from scene_support import Case


def render(c, width, height, stripes, physical=True):
    s=c.scene
    s.reg('CTRL',1)
    s.reg('IRQ_EN',3)
    if physical:
        s.reg('TGT_CFG',int(width == 1280))
    stride=((width+4)*2+31)//32*32
    surface=s.reserve(stride*height,alignment=4096)
    s.memory.write(surface,bytes([165])*(stride*height))
    c.surfaces.append(dict(address=surface,size=stride*height,width=width+4,
                           height=height,stride=stride))
    c.texture(patterned=True)
    c.pixel()
    c.light()
    c.matrix([2/width,0,0,-1,0,-2/height,0,1,0,0,0,.5,0,0,0,1])
    objects=s.records('OBJ',[dict(ALIVE=1,PX=54*256,PY=(height//(2 if width==640 else 8)-2)*256,
                                  VY=4*256,LIFE=8,W=16,H=16,ALPHA=255)])
    c.regions.append(dict(address=objects,size=32,kind='objects'))
    s.reg('OBJ_LIVE_RECT0',0)
    s.reg('OBJ_LIVE_RECT1',width+4 | (height << 16))
    stripe_height=height//stripes
    for stripe in range(stripes):
        y0=stripe*stripe_height
        c.target(TGT_X0=4,TGT_Y0=y0,SC_X0=4,SC_Y0=y0,
                 SC_X1=width+4,SC_Y1=y0+stripe_height,
                 VP_X0=4,VP_Y0=0,VP_W=width,VP_H=height)
        c.clear(0x1234)
        for y in range(20,height,67):
            c.quad(X=4+(y*17)%(width-40),Y=y-15,W=31,H=37)
        for y in range(height//(2 if width==640 else 8),height,
                       height//(2 if width==640 else 8)):
            c.triangles([(16,y-6),(24,y+6),(16,y+6)])
        s.command('OBJ_STEP',ADDR=objects,COUNT=1,STEP=int(stripe==0),DRAW=1)
        s.command('RESOLVE',BASE=surface,STRIDE=stride,X0=4,Y0=y0,
                  X1=width+4,Y1=y0+stripe_height,FXAA=0)
    return surface,objects,stride*height


def build(c,rng):
    for index,(width,height,stripes) in enumerate([(640,360,2),(1280,720,8)]):
        run=c if index==0 else Case()
        if index:
            c.runs.append(run)
        surface,objects,size=render(run,width,height,stripes)
        run.checks.append(lambda gpu,w=width,h=height,a=surface,o=objects,n=size:
                          equivalent(gpu,w,h,a,o,n))


def equivalent(gpu,width,height,surface,objects,size):
    full=Case()
    full_surface,full_objects,_=render(full,width,height,1,physical=False)
    writes=full.scene.finish()
    oracle=GPU(Memory(full.scene.memory.base,full.scene.memory.data),
               reference_size=(width,height)).execute(writes)
    assert gpu.memory.read(surface,size)==oracle.memory.read(full_surface,size)
    assert gpu.memory.read(objects,32)==oracle.memory.read(full_objects,32)
