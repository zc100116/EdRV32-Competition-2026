"""GT-16: gpu-spec 2.3; all CLEAR enables, scissor intersection, depth/stencil probes."""
from scene_support import Case
from pixel_helpers import stencil_probe


def build(c, rng):
    for enables in range(8):
        run = c if enables == 0 else Case()
        if enables:
            c.runs.append(run)
        run.ready()
        run.scene.command('CLEAR', COLOR=0x1357, DEPTH=100, STENCIL=60,
                          EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)
        run.target(SC_X0=8, SC_Y0=9, SC_X1=40, SC_Y1=42)
        run.scene.command('CLEAR', COLOR=0xabcd, DEPTH=50, STENCIL=195,
                          EN_COLOR=enables & 1, EN_DEPTH=enables >> 1 & 1,
                          EN_STENCIL=enables >> 2 & 1)
        run.target()
        run.resolve()
        run.texture(0x07e0)
        run.pixel(DEPTH_FUNC=0)
        run.quad(X=0,Y=0,W=64,H=64,DEPTH=75)
        run.resolve()
        stencil_probe(run)
