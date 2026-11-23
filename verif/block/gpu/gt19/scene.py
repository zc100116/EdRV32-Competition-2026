"""GT-19: gpu-spec 2.9; eight collision targets, list ordering and overflow.
Host scene generator, no clock domain; whole DDR comparison includes list sentinels.
"""

from scene_support import Case


def build(c, rng):
    for index, capacity in enumerate([5, 0, 64]):
        run = c if index == 0 else Case()
        if index:
            c.runs.append(run)
        collision(run, capacity)


def collision(c, capacity):
    c.ready()
    s = c.scene
    s.reg('OBJ_LIVE_RECT0', 0)
    s.reg('OBJ_LIVE_RECT1', (64 << 16) | 64)
    for i in range(8):
        s.reg(f'OBJ_TGT0[{i}]', (16 << 16) | (16+i))
        s.reg(f'OBJ_TGT1[{i}]', (32 << 16) | (32+i))
    hit = s.blob(bytes([0xa5])*256)
    free = s.blob(bytes([0x5a])*256)
    s.reg('OBJ_HIT_BASE', hit)
    s.reg('OBJ_HIT_MAX', capacity)
    s.reg('OBJ_FREE_BASE', free)
    s.reg('OBJ_FREE_MAX', min(capacity, 2) if capacity < 64 else 64)
    base = dict(ALIVE=1, PX=24*256, PY=24*256, COL_HW=2, COL_HH=2,
                W=4, H=4, ALPHA=255)
    variants = [dict(TGT_MASK=255), dict(TGT_MASK=0x55), dict(TGT_MASK=0xaa),
                dict(TGT_MASK=0), dict(TGT_MASK=1, PX=14*256),
                dict(TGT_MASK=1, PX=14*256+255), dict(TGT_MASK=1, PX=15*256),
                dict(TGT_MASK=1, PX=34*256), dict(TGT_MASK=1, PX=33*256),
                dict(TGT_MASK=255, LIFE=1), dict(TGT_MASK=255, PX=64*256),
                dict(TGT_MASK=255, PY=-256), dict(ALIVE=0),
                dict(TGT_MASK=255, LIFE=1)]
    table = s.records('OBJ', [base | item for item in variants])
    c.regions.extend([dict(address=table, size=32*len(variants), kind='objects'),
                      dict(address=hit, size=256, kind='hit'),
                      dict(address=free, size=256, kind='free')])
    s.command('OBJ_STEP', ADDR=table, COUNT=len(variants), STEP=1, DRAW=1)
    c.resolve()

    def check(gpu):
        assert gpu.regs['OBJ_HIT_COUNT'] == 18
        assert gpu.regs['OBJ_FREE_COUNT'] == 4
        assert gpu.regs['OBJ_ALIVE_COUNT'] == 9
        free_capacity = min(capacity, 2) if capacity < 64 else 64
        assert gpu.regs['OBJ_STAT'] == ((1 if capacity < 18 else 0) |
                                        (2 if free_capacity < 4 else 0))
        hits = [(0, i) for i in range(8)] + [(1, i) for i in [0, 2, 4, 6]]
        hits += [(2, i) for i in [1, 3, 5, 7]] + [(6, 0), (8, 0)]
        want = b''.join((obj | (target << 24)).to_bytes(4, 'little')
                        for obj, target in hits[:capacity])
        assert gpu.memory.read(hit, len(want)) == want, 'hit list object/target order'
        assert gpu.memory.read(hit+len(want), 256-len(want)) == bytes([0xa5])*(256-len(want))
        want = b''.join(i.to_bytes(4, 'little') for i in [9, 10, 11, 13][:free_capacity])
        assert gpu.memory.read(free, len(want)) == want, 'free list object order'
        assert gpu.memory.read(free+len(want), 256-len(want)) == bytes([0x5a])*(256-len(want))
    c.checks.append(check)
