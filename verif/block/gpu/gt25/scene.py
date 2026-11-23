"""GT-25: gpu-spec 7; 180 MHz/default-DDR loads and fixed-overhead pairs.
Host generator; public DOORBELL-to-drain timing comes from the RTL bench only.
"""
from scene_support import Case

WORKLOADS = ['quad', 'nearest', 'bilinear', 'trilinear', 'palette_i4', 'palette_i8',
             'vertex', 'setup', 'objects', 'resolve']


def build(c, rng):
    for index, name in enumerate(WORKLOADS):
        run = c if index == 0 else Case()
        if index:
            c.runs.append(run)
        run.ready(SC_X1=640, SC_Y1=180, VP_W=640, VP_H=180)
        run.command_timing = True
        if name == 'quad':
            indexed(run, 0, 0)
            run.pixel(BL_FS=2, BL_FD=3, DEPTH_FUNC=1, DEPTH_WRITE=0)
            records = [dict(X=(i % 32)*16, Y=(i//32)*16,
                            W=16, H=16, ALPHA=128) for i in range(256)]
            address = run.scene.records('QUAD', records)
            pair(run, 'DRAW_QUAD', address, 256)
        elif name in ['nearest', 'bilinear', 'trilinear', 'palette_i4', 'palette_i8']:
            sample = {'nearest': 0, 'bilinear': 1, 'trilinear': 2,
                      'palette_i4': 1, 'palette_i8': 1}[name]
            if name.startswith('palette'):
                indexed(run, int(name[-1] == '8'), sample)
            else:
                levels = [[(i*997) & 65535 for i in range(n*n)]
                          for n in [16, 8, 4, 2, 1]]
                source, size = run.scene.texture(levels, format=2, width=16, height=16)
                run.scene.command('TEX_LOAD', SRC=source, DST=0, BYTES=size)
                run.scene.command('SET_TEX', OFFSET=0, LOG2_W=4, LOG2_H=4,
                                  FORMAT=2, LEVELS=5, SAMPLE=sample, LOD_BIAS=8)
            vertices = [dict(X=-1, Y=-1, Z=1, NZ=127, U=137, V=251, COLOR=65535),
                        dict(X=1, Y=-1, Z=1, NZ=127, U=65000, V=571, COLOR=65535),
                        dict(X=0, Y=1, Z=1, NZ=127, U=907, V=64000, COLOR=65535)]
            if name == 'nearest':
                # 1:1 horizontal UVs make the four adjacent lanes conflict-free.
                run.target(SC_X1=128, SC_Y1=128, VP_W=128, VP_H=128)
                # u=x/2, v=x: four lanes visit all four parity banks.
                vertices[0].update(U=0, V=0)
                vertices[1].update(U=64*256, V=128*256)
                vertices[2].update(U=32*256, V=64*256)
            address = run.scene.records('VERTEX', vertices)
            pair(run, 'DRAW_TRI', address, 1)
        elif name in ['vertex', 'setup']:
            # Identical input order; culling isolates front-end work from raster work.
            run.pixel(CULL=2 if name == 'vertex' else 0)
            run.target(SC_X1=640, SC_Y1=180, VP_X0=800, VP_Y0=0, VP_W=64, VP_H=64)
            triangle = [dict(X=-1, Y=-1, Z=1, NZ=127, COLOR=65535),
                        dict(X=1, Y=-1, Z=1, NZ=127, COLOR=65535),
                        dict(X=0, Y=1, Z=1, NZ=127, COLOR=65535)]
            address = run.scene.records('VERTEX', triangle*256)
            pair(run, 'DRAW_TRI', address, 256)
        elif name == 'objects':
            run.scene.reg('OBJ_LIVE_RECT0', 0)
            run.scene.reg('OBJ_LIVE_RECT1', (180 << 16) | 640)
            address = run.scene.records('OBJ', [dict(ALIVE=1, PX=(i % 600)*256,
                                                     PY=40*256, VX=128, W=4, H=4,
                                                     ALPHA=255) for i in range(4096)])
            run.regions.append(dict(address=address, size=32*4096, kind='objects'))
            pair(run, 'OBJ_STEP', address, 4096, STEP=1, DRAW=0)
        else:
            surface = run.scene.blob(bytes([0xa5])*(1280*360), alignment=4096)
            for y in [0, 180]:
                run.target(TGT_Y0=y, SC_Y0=y, SC_X1=640, SC_Y1=y+180,
                           VP_W=640, VP_H=360)
                run.clear(color=0x39e7)
                run.scene.command('RESOLVE', BASE=surface, STRIDE=1280, X0=0, Y0=y,
                                  X1=640, Y1=y+180, FXAA=1, FXAA_TH=32)
            run.surfaces.append(dict(address=surface, size=1280*360,
                                     width=640, height=360, stride=1280))
        if name != 'resolve':
            run.resolve(width=640, height=180)


def pair(c, command, address, count, **fields):
    c.scene.command(command, ADDR=address, COUNT=0, **fields)
    c.scene.command(command, ADDR=address, COUNT=count, **fields)


def indexed(c, fmt, sample):
    s = c.scene
    palette = s.records('PAL_ENTRY', [dict(RGB565=(i*4097) & 65535, A4=15)
                                      for i in range(256)])
    s.command('PAL_LOAD', SRC=palette, GROUP=0, ENTRIES=256)
    source, size = s.texture([[i % (16 if fmt == 0 else 256) for i in range(256)]],
                             format=fmt, width=16, height=16)
    s.command('TEX_LOAD', SRC=source, DST=0, BYTES=size)
    s.command('SET_TEX', OFFSET=0, LOG2_W=4, LOG2_H=4,
              FORMAT=fmt, LEVELS=1, SAMPLE=sample)
