"""GT-22: gpu-spec 5; ABORT while draw, texture DMA, objects and resolve run.
Host generator; only guaranteed IDLE/error/completion state is compared after drain.
"""
from scene_support import Case
from tools.gpu.scene import unpack


def build(c, rng):
    for index, kind in enumerate(['draw', 'texture', 'objects', 'resolve']):
        run = c if index == 0 else Case()
        if index:
            c.runs.append(run)
        run.ready(SC_X1=640, SC_Y1=180, VP_W=640, VP_H=180)
        s = run.scene
        if kind == 'draw':
            run.triangles([(-1, -1, 1), (1, -1, 1), (0, 1, 1)]*8)
            address = unpack('CMD_DRAW_TRI', s.commands[-1])['ADDR']
        elif kind == 'texture':
            address = s.blob(bytes(rng.randrange(256) for _ in range(65536)))
            s.command('TEX_LOAD', SRC=address, DST=0, BYTES=65536)
        elif kind == 'objects':
            s.reg('OBJ_LIVE_RECT0', 0)
            s.reg('OBJ_LIVE_RECT1', (180 << 16) | 640)
            address = s.records('OBJ', [dict(ALIVE=1, PX=32*256, PY=32*256,
                                            VX=256, W=4, H=4, ALPHA=255)]*4096)
            run.regions.append(dict(address=address, size=32*4096, kind='objects'))
            s.command('OBJ_STEP', ADDR=address, COUNT=4096, STEP=1, DRAW=1)
        else:
            address = run.resolve(width=640, height=180)
        channel = 'write_address' if kind == 'resolve' else 'read_address'
        run.abort = {channel: (address, address), 'after': 32}
        run.compare_ddr = False
        run.checked_registers = ['STATUS', 'IRQ_STAT', 'ERR_CODE', 'DONE_COUNT']
        # No earlier command list has completed; ABORT does not generate DONE.
        run.expected_registers = dict(STATUS=2, IRQ_STAT=0, ERR_CODE=0, DONE_COUNT=0)
