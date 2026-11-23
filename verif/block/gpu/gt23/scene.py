"""GT-23: gpu-spec 4; reset, ID, register access and functional PERF events.
Host scene generator; PERF0/5–8 are timing observations from the RTL bench only.
"""
from tools.gpu.scene import SCHEMA


def build(c, rng):
    names = []
    for item in SCHEMA['registers']:
        dims = item['dimensions']
        names.extend(item['name'] + (f'[{i}]' if dims else '')
                     for i in range(dims[0]['count'] if dims else 1))
    c.reset_registers = names
    c.sample_registers = names
    c.ready()
    s = c.scene
    c.pixel(COLOR_WRITE=0, DEPTH_WRITE=0)
    # These passing fragments count even though neither color nor depth is written.
    c.quad(X=0, Y=0, W=4, H=4)
    c.quad(X=80, Y=80, W=4, H=4)
    # Degenerate triangles contribute source vertices but no rasterized triangles.
    c.triangles([(0, 0, 1)]*3)
    c.pixel()
    c.triangles([(-1, -1, 1), (1, -1, 1), (0, 1, 1)])
    objects = s.records('OBJ', [dict(ALIVE=1, PX=32*256, PY=32*256,
                                    W=4, H=4, ALPHA=255), dict(ALIVE=0)])
    s.command('OBJ_STEP', ADDR=objects, COUNT=2, STEP=0, DRAW=1)
    c.resolve()
    for name in ['ID', 'STATUS', 'ERR_CODE', 'DONE_COUNT', 'OBJ_HIT_COUNT',
                 'OBJ_FREE_COUNT', 'OBJ_ALIVE_COUNT', 'OBJ_STAT']:
        s.reg(name, 0xffffffff)
    for index in range(16):
        s.reg(f'PERF[{index}]', 0xffffffff)

    def check(gpu):
        assert gpu.regs['ID'] >> 16 == 6
        assert gpu.regs['PERF[1]'] == 6
        assert gpu.regs['PERF[2]'] == 1
        assert gpu.regs['PERF[3]'] == 3
        assert gpu.regs['PERF[4]'] > 16
        assert gpu.regs['DONE_COUNT'] == 1
        assert all(gpu.regs[f'PERF[{i}]'] == 0 for i in range(9, 16))
    c.checks.append(check)

    # Separate reset runs observe both polarities of every software-owned bit.
    from scene_support import Case
    for pattern in [0x55555555, 0xaaaaaaaa]:
        run = Case()
        run.ready()
        run.sample_registers = names
        for item in SCHEMA['registers']:
            if item['access'] != 'RW' or item['name'] in ['CTRL', 'IRQ_EN']:
                continue
            dims = item['dimensions']
            mask = sum(((1 << field['width'])-1) << field['lsb']
                       for field in item['fields']) if item['fields'] else 0xffffffff
            for i in range(dims[0]['count'] if dims else 1):
                name = item['name'] + (f'[{i}]' if dims else '')
                run.scene.reg(name, pattern & mask)
        c.runs.append(run)
