"""GT-12: gpu-spec 2.6; sizes 8–256, all formats/samplers/mips, bias/wrap/preload."""
from scene_support import Case
from pixel_helpers import palette, pixel_matrix


def build(c, rng):
    first = True
    for format in range(3):
        for log_size in range(3, 9):
            for sample in range(3):
                run = c if first else Case()
                if not first:
                    c.runs.append(run)
                first = False
                run.ready()
                pixel_matrix(run)
                size = 1 << log_size
                levels = []
                for level in range(log_size+1):
                    side = max(1, size >> level)
                    levels.append([((x*13+y*37+level*7) % (16 if format == 0 else 256))
                                   if format != 2 else (x*131+y*4099+level*7391) & 65535
                                   for y in range(side) for x in range(side)])
                source, count = run.scene.texture(levels, format=format, width=size, height=size)
                run.scene.command('TEX_LOAD', SRC=source, DST=0, BYTES=count)
                if format != 2:
                    for group in range(16):
                        palette(run, group, alpha=15)
                for level in range(log_size+1):
                    for adjacent in range(2):
                        bias = max(-128, min(127, (level-1)*16 + adjacent*8))
                        group = (2*level+adjacent) % 16
                        run.scene.command('SET_TEX', OFFSET=0, LOG2_W=log_size,
                                          LOG2_H=log_size, FORMAT=format,
                                          LEVELS=log_size+1, SAMPLE=sample,
                                          LOD_BIAS=bias, PAL_GROUP=group)
                        origin = (size-2 if size < 128 else 120)*256 + rng.choice([0,64,128,255])
                        records = [dict(X=x, Y=y, Z=1, NZ=127, COLOR=0xffff, U=u, V=v)
                                   for x,y,u,v in [(4,4,origin,origin),
                                                  (12,4,origin+4096,origin),
                                                  (4,12,origin,origin+4096)]]
                        address = run.scene.records('VERTEX', records)
                        run.scene.command('DRAW_TRI', ADDR=address, COUNT=1)
                        run.resolve(16,16)
