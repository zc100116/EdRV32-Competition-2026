"""pixel_helpers.py: gpu-spec 2.6–2.7; palette setup and external stencil probes.
Host scene construction. Probes only use drawing and RESOLVE, never DUT internals.
"""


def palette(c, group, entries=256, alpha=None):
    values = [dict(RGB565=((index*1973 + group*3907) & 65535),
                   A4=(index % 16 if alpha is None else alpha)) for index in range(entries)]
    address = c.scene.records('PAL_ENTRY', values)
    c.scene.command('PAL_LOAD', SRC=address, GROUP=group, ENTRIES=entries)


def stencil_probe(c, width=64, height=64):
    c.target(SC_X1=width, SC_Y1=height)
    c.scene.command('CLEAR', COLOR=0, EN_COLOR=1)
    for bit in range(8):
        c.texture(1 << bit)
        c.pixel(ST_FUNC=2, ST_REF=1 << bit, ST_RMASK=1 << bit,
                ST_WMASK=0, BL_FS=1, BL_FD=1)
        c.quad(X=0, Y=0, W=width, H=height, DEPTH=0)
    c.resolve(width, height)


def pixel_matrix(c):
    c.matrix([1/32, 0, 0, -1, 0, -1/32, 0, 1, 0, 0, 0, .5, 0, 0, 0, 1])
