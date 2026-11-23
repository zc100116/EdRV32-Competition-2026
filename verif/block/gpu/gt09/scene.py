"""GT-09: gpu-spec 2.7; 8 functions, 6 operations, masks and all reachable outcomes."""
from pixel_helpers import stencil_probe


def build(c, rng):
    c.ready()
    samples = [(0, 255, 255, 255), (255, 0, 255, 15), (85, 170, 15, 240),
               (170, 170, 0, 255), (123, 123, 255, 0)]
    index = 0
    for function in range(8):
        for operation in range(6):
            for ref, initial, read_mask, write_mask in samples:
                for depth in [99, 101]:
                    cell = index % 256
                    if cell == 0:
                        c.target()
                        c.clear()
                        c.texture()
                    x, y = cell % 16*4, cell//16*4
                    c.target(SC_X0=x, SC_Y0=y, SC_X1=x+4, SC_Y1=y+4)
                    c.scene.command('CLEAR', COLOR=0, DEPTH=100, STENCIL=initial,
                                    EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)
                    c.pixel(COLOR_WRITE=0, DEPTH_FUNC=0, ST_FUNC=function, ST_REF=ref,
                            ST_RMASK=read_mask, ST_WMASK=write_mask,
                            ST_SFAIL=operation, ST_ZFAIL=operation, ST_ZPASS=operation)
                    c.quad(X=x, Y=y, W=4, H=4, DEPTH=depth)
                    index += 1
                    if index % 256 == 0:
                        stencil_probe(c)
    if index % 256:
        stencil_probe(c)
