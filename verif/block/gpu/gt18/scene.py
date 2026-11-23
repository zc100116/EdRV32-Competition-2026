"""GT-18: gpu-spec 2.9; advance, expiry, wrapping and STEP=0 preservation.
Host scene generator, no clock domain; expected bytes come from the GPU model.
"""
from tools.gpu.scene import LAYOUTS, pack


def build(c, rng):
    c.ready()
    s = c.scene
    free = s.blob(bytes([0xa5])*256)
    hit = s.blob(bytes([0xa5])*256)
    for name, value in [('OBJ_FREE_BASE', free), ('OBJ_FREE_MAX', 64),
                        ('OBJ_HIT_BASE', hit), ('OBJ_HIT_MAX', 64)]:
        s.reg(name, value)
    base = dict(ALIVE=1, PX=20*256, PY=20*256, W=7, H=9, ALPHA=255,
                COL_HW=2, COL_HH=2, LIFE=0, DEPTH=100)
    variants = [dict(VX=256, VY=-256, AX=8, AY=-8), dict(LIFE=1),
                dict(LIFE=2), dict(ALIVE=0), dict(PX=32767*256, VX=32767, AX=16),
                dict(PX=-32768*256, VX=-32768, AX=-16),
                dict(VX=32767, AX=16), dict(VY=-32768, AY=-16),
                dict(PX=32767*256, VX=256), dict(PY=-32768*256, VY=-1)]
    variants += [dict(PX=rng.randrange(-8, 72)*256+rng.randrange(256),
                      PY=rng.randrange(-8, 72)*256+rng.randrange(256),
                      VX=rng.randrange(-32768, 32768), VY=rng.randrange(-32768, 32768),
                      AX=rng.randrange(-32768, 32768), AY=rng.randrange(-32768, 32768),
                      LIFE=rng.choice([0, 1, 2, 65535])) for _ in range(32)]
    records = bytearray()
    for variant in variants:
        fields = base | dict(U0=rng.randrange(256), V0=rng.randrange(256),
                             FLIP_H=rng.randrange(2), FLIP_V=rng.randrange(2),
                             PAL_GROUP=rng.randrange(16), DEPTH=rng.randrange(65536))
        raw = bytearray(pack('OBJ', **(fields | variant)))
        # Reserved bits in words 0, 1, 2 and 5 must survive the 32-byte writeback.
        raw[0] |= 0xaa
        raw[7] = rng.randrange(256)
        raw[11] = rng.randrange(256)
        raw[22:24] = bytes([0x5a, 0xc3])
        records.extend(raw)
    table = s.blob(records)
    c.regions.extend([dict(address=table, size=len(records), kind='objects'),
                      dict(address=free, size=256, kind='free'),
                      dict(address=hit, size=256, kind='hit')])
    preserved = sum(((1 << field['width'])-1)
                    << (int(field['offset'], 0)*8 + field['lsb'])
                    for field in LAYOUTS['OBJ']['fields']
                    if field['name'] in ['ALIVE', 'PX', 'PY', 'VX', 'VY', 'LIFE'])
    preserved = ((1 << 256)-1) ^ preserved
    s.command('OBJ_STEP', ADDR=table, COUNT=len(variants), STEP=1, DRAW=1)
    c.resolve()
    # An out-of-live-area object with LIFE=1 must still draw and remain unchanged.
    frozen = s.records('OBJ', [base | dict(PX=32*256, PY=32*256, LIFE=1,
                                          TGT_MASK=255, VX=32767, VY=-32768)])
    c.regions.append(dict(address=frozen, size=32, kind='step0-objects'))
    # These setup registers apply to both commands: the wrap/expiry vectors still
    # cover advancement, while the second table proves STEP=0 ignores live bounds.
    s.reg('OBJ_LIVE_RECT0', 0)
    s.reg('OBJ_LIVE_RECT1', (24 << 16) | 24)
    s.command('OBJ_STEP', ADDR=frozen, COUNT=1, STEP=0, DRAW=1)
    c.resolve()
    original = s.memory.read(frozen, 32)

    def check(gpu):
        assert gpu.memory.read(frozen, 32) == original, 'STEP=0 changed object bytes'
        for index in range(len(variants)):
            before = int.from_bytes(records[index*32:(index+1)*32], 'little')
            after = int.from_bytes(gpu.memory.read(table+index*32, 32), 'little')
            assert before & preserved == after & preserved, f'object {index} preserved bits'
        assert gpu.regs['OBJ_HIT_COUNT'] == 0
        assert gpu.regs['OBJ_FREE_COUNT'] == 0
        assert gpu.regs['OBJ_ALIVE_COUNT'] == 1
        assert gpu.regs['OBJ_STAT'] == 0
    c.checks.append(check)
