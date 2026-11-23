"""GT-20: gpu-spec 2.10; AA thresholds, original neighbors, shapes and stride.
Host scene generator, no clock domain; sentinels cover all bytes outside RESOLVE.
"""


def build(c, rng):
    from scene_support import Case
    for wide, width, height in [(0, 640, 180), (1, 1280, 90)]:
        run = c if wide == 0 else Case()
        if wide:
            c.runs.append(run)
        run.ready(SC_X1=width, SC_Y1=height, VP_W=width, VP_H=height)
        run.scene.reg('TGT_CFG', wide)
        render(run, width, height)


def render(c, width, height):
    c.target(SC_X1=width, SC_Y1=height, VP_W=width, VP_H=height)
    c.clear(color=0)
    c.texture(patterned=True)
    for x, y, w, h in [(0, 0, 19, 17), (15, 14, 33, 29),
                        (width-33, height-20, 33, 20), (32, 30, 1, 32)]:
        c.quad(X=x, Y=y, W=w, H=h)
    s = c.scene
    for aa, threshold in [(0, 0), (1, 0), (1, 1), (1, 64), (1, 255)]:
        stride = (width*2+63)//32*32
        size = stride*(height+2)
        address = s.blob(bytes([0xa5])*size, alignment=4096)
        s.command('RESOLVE', BASE=address, STRIDE=stride, X0=16, Y0=1,
                  X1=width-16, Y1=height-1, FXAA=aa, FXAA_TH=threshold)
        c.surfaces.append(dict(address=address, size=size, width=width,
                               height=height+2, stride=stride))
