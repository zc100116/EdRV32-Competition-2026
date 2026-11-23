"""GT-14: gpu-spec 2.7, 5; adjacent commands revisit the same packed pixel words."""
from pixel_helpers import palette, pixel_matrix


def build(c, rng):
    c.ready()
    pixel_matrix(c)
    palette(c, 0, entries=16, alpha=8)
    source,count = c.scene.texture([[(x+3*y)%16 for y in range(8) for x in range(8)]],
                                   format=0, width=8, height=8)
    c.scene.command('TEX_LOAD', SRC=source, DST=0, BYTES=count)
    c.scene.command('SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3, FORMAT=0, LEVELS=1)
    c.pixel(BL_FS=2, BL_FD=3)
    for index in range(256):
        x,y = 7+rng.randrange(3), 7+rng.randrange(3)
        c.quad(X=x, Y=y, W=rng.randrange(1,6), H=rng.randrange(1,6),
               U0=rng.randrange(8), V0=rng.randrange(8), ALPHA=rng.randrange(32,225))
        c.triangles([(x,y),(x+5,y),(x,y+5)])
        if index % 16 == 15:
            c.resolve(16,16)
