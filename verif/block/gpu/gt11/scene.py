"""GT-11: gpu-spec 2.6; all formats/banks, 16 palette groups and alpha discard."""
from scene_support import Case
from pixel_helpers import palette, stencil_probe


def build(c, rng):
    for format in range(3):
        run = c if format == 0 else Case()
        if format:
            c.runs.append(run)
        run.ready()
        run.scene.command('CLEAR', COLOR=0x1234, DEPTH=77, STENCIL=165,
                          EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)
        for group in range(16):
            palette(run, group)
        texels = [((x+3*y) % 16 if format == 0 else (x+16*y) % 256) if format != 2
                  else (x*3761+y*7927) & 65535 for y in range(16) for x in range(16)]
        source, count = run.scene.texture([texels], format=format, width=16, height=16)
        run.scene.command('TEX_LOAD', SRC=source, DST=0, BYTES=count)
        run.scene.command('SET_TEX', OFFSET=0, LOG2_W=4, LOG2_H=4,
                          FORMAT=format, LEVELS=1)
        for group in range(16):
            run.pixel(DEPTH_WRITE=1, ST_ZPASS=2, ST_REF=group+17, BL_FS=2, BL_FD=3)
            run.quad(X=group % 4*16, Y=group//4*16, W=16, H=16,
                     PAL_GROUP=group, DEPTH=50)
        run.resolve()
        run.texture(0x07e0)
        run.pixel(DEPTH_FUNC=0)
        run.quad(X=0, Y=0, W=64, H=64, DEPTH=60)
        run.resolve()
        stencil_probe(run)
