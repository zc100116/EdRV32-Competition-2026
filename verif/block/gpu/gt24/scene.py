"""GT-24: gpu-spec 2–6; seeded mixed command/state regression.
Host scene generator, no clock domain; all expected DDR and counters use the model.
"""


def build(c, rng):
    c.ready()
    s = c.scene
    for name, value in [('OBJ_LIVE_RECT0', 0xfff0fff0),
                        ('OBJ_LIVE_RECT1', (80 << 16) | 80),
                        ('OBJ_HIT_MAX', 128), ('OBJ_FREE_MAX', 128)]:
        s.reg(name, value)
    for kind in ['HIT', 'FREE']:
        address = s.blob(bytes([0xa5])*512)
        s.reg(f'OBJ_{kind}_BASE', address)
        c.regions.append(dict(address=address, size=512, kind=kind.lower()))
    for i in range(8):
        x, y = rng.randrange(32), rng.randrange(32)
        s.reg(f'OBJ_TGT0[{i}]', (y << 16) | x)
        s.reg(f'OBJ_TGT1[{i}]', ((y+24) << 16) | (x+24))
    for batch in range(12):
        x0, y0 = rng.randrange(0, 12), rng.randrange(0, 12)
        c.target(SC_X0=x0, SC_Y0=y0, SC_X1=rng.randrange(48, 65),
                 SC_Y1=rng.randrange(48, 65), VP_X0=rng.randrange(-4, 5),
                 VP_Y0=rng.randrange(-4, 5), VP_W=rng.randrange(32, 73),
                 VP_H=rng.randrange(32, 73))
        c.pixel(DEPTH_FUNC=rng.randrange(2), DEPTH_WRITE=rng.randrange(2),
                COLOR_WRITE=rng.randrange(2), CULL=rng.randrange(3),
                ST_FUNC=rng.randrange(8), ST_REF=rng.randrange(256),
                ST_RMASK=rng.randrange(256), ST_WMASK=rng.randrange(256),
                ST_SFAIL=rng.randrange(6), ST_ZFAIL=rng.randrange(6),
                ST_ZPASS=rng.randrange(6), BL_FS=rng.randrange(10),
                BL_FD=rng.randrange(10), BL_OP=rng.randrange(5),
                BL_CONST_A=rng.randrange(256))
        # Change texture format, palette group, filtering and LOD between draws.
        fmt, sample, group = batch % 3, (batch//3) % 3, batch % 16
        levels = []
        for size in [8, 4, 2, 1]:
            limit = [16, 256, 65536][fmt]
            levels.append([rng.randrange(limit) for _ in range(size*size)])
        address, size = s.texture(levels, format=fmt, width=8, height=8)
        s.command('TEX_LOAD', SRC=address, DST=0, BYTES=size)
        if fmt != 2:
            palette = s.records('PAL_ENTRY', [dict(RGB565=rng.randrange(65536),
                                                  A4=rng.randrange(16)) for _ in range(256)])
            s.command('PAL_LOAD', SRC=palette, GROUP=group, ENTRIES=256)
        s.command('SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3, FORMAT=fmt,
                  LEVELS=4, PAL_GROUP=group, SAMPLE=sample,
                  LOD_BIAS=rng.randrange(-32, 33))
        values = [1, 0, 0, rng.uniform(-.2, .2), 0, 1, 0, rng.uniform(-.2, .2),
                  0, 0, .5, 0, rng.uniform(-.3, .3), 0, 0, 1]
        c.matrix(values)
        c.light(LX=0, LY=0, LZ=16384,
                DIR_RGB=rng.randrange(1 << 24), AMB_RGB=rng.randrange(1 << 24))
        choices = ['tri', 'quad', 'obj', 'clear']
        rng.shuffle(choices)
        for choice in choices:
            if choice == 'tri':
                points = [(rng.randrange(-2, 3), rng.randrange(-2, 3),
                           rng.randrange(1, 4)) for _ in range(6)]
                c.triangles(points, COLOR=rng.randrange(65536),
                            U=rng.randrange(65536), V=rng.randrange(65536))
            elif choice == 'quad':
                for _ in range(4):
                    c.quad(X=rng.randrange(-16, 64), Y=rng.randrange(-16, 64),
                           W=rng.randrange(1, 65), H=rng.randrange(1, 65),
                           U0=rng.randrange(256), V0=rng.randrange(256),
                           FLIP_H=rng.randrange(2), FLIP_V=rng.randrange(2),
                           PAL_GROUP=group, ALPHA=rng.randrange(256),
                           DEPTH=rng.randrange(65536))
            elif choice == 'obj':
                records = [dict(ALIVE=rng.randrange(2), PX=rng.randrange(-8, 72)*256,
                                PY=rng.randrange(-8, 72)*256, VX=rng.randrange(-512, 513),
                                VY=rng.randrange(-512, 513), AX=rng.randrange(-2048, 2049),
                                AY=rng.randrange(-2048, 2049), LIFE=rng.choice([0, 1, 10]),
                                COL_HW=4, COL_HH=4, TGT_MASK=rng.randrange(256),
                                W=rng.randrange(1, 17), H=rng.randrange(1, 17),
                                ALPHA=rng.randrange(256), PAL_GROUP=group) for _ in range(8)]
                table = s.records('OBJ', records)
                c.regions.append(dict(address=table, size=256, kind='objects'))
                s.command('OBJ_STEP', ADDR=table, COUNT=8, STEP=batch % 2, DRAW=1)
            else:
                s.command('CLEAR', COLOR=rng.randrange(65536), DEPTH=rng.randrange(65536),
                          STENCIL=rng.randrange(256), EN_COLOR=rng.randrange(2),
                          EN_DEPTH=rng.randrange(2), EN_STENCIL=rng.randrange(2))
        c.resolve()
