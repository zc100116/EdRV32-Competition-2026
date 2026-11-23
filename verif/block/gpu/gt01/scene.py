"""GT-01: gpu-spec 2.2, 2.3, 6; serial command effects and undefined opcode."""


def build(c, rng):
    c.ready()
    s = c.scene
    palette = s.records('PAL_ENTRY', [dict(RGB565=0xf800, A4=15)] * 16)
    s.command('PAL_LOAD', SRC=palette, GROUP=0, ENTRIES=16)
    c.triangles([(-1, -1), (1, -1), (0, 1)])
    s.command('SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3, FORMAT=0, LEVELS=1)
    c.quad()
    c.resolve()
    c.texture(0x07e0)
    c.quad(X=16, Y=16)
    objects = s.records('OBJ', [dict(ALIVE=1, PX=24*256, PY=24*256,
                                   W=8, H=8, ALPHA=255, LIFE=0)])
    c.regions.append(dict(address=objects, size=32, kind='objects'))
    hit = s.reserve(32)
    free = s.reserve(32)
    c.regions.extend([dict(address=hit, size=32, kind='hits'),
                      dict(address=free, size=32, kind='free')])
    for name, value in [('OBJ_LIVE_RECT0', 0), ('OBJ_LIVE_RECT1', 64 | (64 << 16)),
                        ('OBJ_HIT_BASE', hit), ('OBJ_HIT_MAX', 8),
                        ('OBJ_FREE_BASE', free), ('OBJ_FREE_MAX', 8)]:
        s.reg(name, value)
    s.command('OBJ_STEP', ADDR=objects, COUNT=1, STEP=1, DRAW=1)
    c.resolve()
    # The following CLEAR must never execute, and DONE must remain clear.
    s.commands.append(bytes([0xff]) + bytes(31))
    c.clear(0x001f)
    c.resolve()
