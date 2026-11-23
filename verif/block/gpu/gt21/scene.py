"""GT-21: gpu-spec 6; command/vertex/texture read and resolve write errors.
Host generator; ERR2 and AXI transaction draining are the public observations.
"""
from scene_support import Case
from tools.gpu.scene import unpack


def build(c, rng):
    for index, kind in enumerate(['command', 'vertex', 'texture', 'resolve']):
        run = c if index == 0 else Case()
        if index:
            c.runs.append(run)
        run.ready()
        run.triangles([(-1, -1, 1), (1, -1, 1), (0, 1, 1)])
        surface = run.resolve()
        s = run.scene
        if kind == 'command':
            address = (s.memory.base + len(s.memory.data) + 63) & ~63
        elif kind == 'vertex':
            command = next(item for item in s.commands if item[0] == 0x20)
            address = unpack('CMD_DRAW_TRI', command)['ADDR']
        elif kind == 'texture':
            command = next(item for item in s.commands if item[0] == 0x30)
            address = unpack('CMD_TEX_LOAD', command)['SRC']
        else:
            address = surface
        channel = 'write' if kind == 'resolve' else 'read'
        run.axi_errors[channel] = dict(first=address, last=address)
        # Partially completed rendering/writes on ERROR have no specified contents.
        run.compare_ddr = False
        run.checked_registers = ['STATUS', 'IRQ_STAT', 'ERR_CODE', 'DONE_COUNT']

        def check(gpu):
            assert gpu.regs['ERR_CODE'] == 2
            assert gpu.regs['IRQ_STAT'] == 2
            assert gpu.regs['DONE_COUNT'] == 0
        run.checks.append(check)
