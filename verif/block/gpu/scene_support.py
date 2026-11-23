"""scene_support.py: gpu-spec 2–4; public scene helpers for GPU block tests.
Host generator, no clock domain. All target observations are RESOLVE surfaces.
"""
from tools.gpu.scene import Scene


class Case:
    def __init__(self):
        self.scene = Scene()
        self.surfaces = []
        self.regions = []
        self.checks = []

    def target(self, **changes):
        fields = dict(TGT_X0=0, TGT_Y0=0, SC_X0=0, SC_Y0=0, SC_X1=64, SC_Y1=64,
                      VP_X0=0, VP_Y0=0, VP_W=64, VP_H=64)
        fields.update(changes)
        self.scene.command('SET_TARGET', **fields)

    def pixel(self, **changes):
        fields = dict(DEPTH_FUNC=1, DEPTH_WRITE=0, COLOR_WRITE=1, CULL=0,
                      ST_FUNC=7, ST_RMASK=255, ST_WMASK=255, BL_FS=1, BL_FD=0, BL_OP=0)
        fields.update(changes)
        self.scene.command('SET_PIXEL', **fields)

    def clear(self, color=0, depth=65535):
        self.scene.command('CLEAR', COLOR=color, DEPTH=depth, STENCIL=0,
                           EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)

    def texture(self, color=0xffff, patterned=False):
        texels = [(0xf800, 0x07e0, 0x001f, 0xffff)[(x//2 + y//2) % 4]
                  if patterned else color for y in range(8) for x in range(8)]
        address, size = self.scene.texture([texels], format=2, width=8, height=8)
        self.scene.command('TEX_LOAD', SRC=address, DST=0, BYTES=size)
        self.scene.command('SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3,
                           FORMAT=2, LEVELS=1, SAMPLE=0)

    def matrix(self, values=None):
        if values is None:
            values = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, .5, 0, 0, 0, 0, 1]
        self.scene.command('SET_MATRIX', ADDR=self.scene.matrix(values))

    def light(self, **changes):
        fields = dict(LX=0, LY=0, LZ=16384, DIR_RGB=0, AMB_RGB=0xffffff)
        fields.update(changes)
        self.scene.command('SET_LIGHT', **fields)

    def ready(self, **target):
        self.scene.reg('CTRL', 1)
        self.scene.reg('IRQ_EN', 3)
        self.target(**target)
        self.clear()
        self.pixel()
        self.texture()
        self.matrix()
        self.light()

    def triangles(self, points, **changes):
        records = []
        for index, point in enumerate(points):
            item = dict(X=point[0], Y=point[1], Z=point[2] if len(point) > 2 else 1,
                        NX=0, NY=0, NZ=127, U=(index % 3)*7*256,
                        V=(index//2 % 2)*7*256, COLOR=0xffff)
            item.update(changes)
            records.append(item)
        address = self.scene.records('VERTEX', records)
        self.scene.command('DRAW_TRI', ADDR=address, COUNT=len(records)//3)

    def quad(self, **changes):
        fields = dict(X=8, Y=8, W=32, H=32, ALPHA=255, DEPTH=100)
        fields.update(changes)
        address = self.scene.records('QUAD', [fields])
        self.scene.command('DRAW_QUAD', ADDR=address, COUNT=1)

    def resolve(self, width=64, height=64):
        stride = (width*2 + 31)//32*32
        address = self.scene.reserve(stride*height, alignment=4096)
        # A sentinel checks untouched padding and areas outside the resolve rectangle.
        self.scene.memory.write(address, bytes([0xa5])*(stride*height))
        self.scene.command('RESOLVE', BASE=address, STRIDE=stride, X0=0, Y0=0,
                           X1=width, Y1=height)
        self.surfaces.append(dict(address=address, size=stride*height,
                                  width=width, height=height, stride=stride))
        return address
