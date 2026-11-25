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
    # v0.4: 1/2/3-pixel groups, shared triangle edges, and odd target/scissor row limits.
    boundary = Case()
    c.runs.append(boundary)
    boundary.ready(TGT_Y0=1, SC_Y0=1, SC_Y1=181, VP_H=256)
    boundary.matrix([1/32, 0, 0, -1, 0, -1/128, 0, 1,
                     0, 0, 0, .5, 0, 0, 0, 1])
    lod_texture(boundary)
    for y in (0, 3, 178, 180):
        boundary.triangles([(4,y,1), (6,y,1), (4,y+2,1),
                            (8,y,1), (10,y,1), (10,y+2,1),
                            (12,y,1), (14,y+2,1), (12,y+2,1),
                            (16,y,1), (18,y,1), (17,y+2,1)])
    boundary.target(TGT_Y0=1, SC_Y0=3, SC_Y1=7, VP_H=256)
    boundary.triangles([(0,2,1), (16,2,1), (0,8,1)])
    resolve_rows(boundary, 32, 1, 181)

    # Constant world X gives Q = (31.5 - screen_x) or (31 - screen_x).
    # The covered x=30.5 pixel shares its 2x2 group with Q=0 or negative at x=31.5.
    # W spans the near-plane value 1/16 to 16, exercising extrapolation beyond the edge.
    for offset in (1/1024, 1/512):
        helper = Case()
        c.runs.append(helper)
        helper.ready()
        helper.matrix([1/32, 0, -offset, 0, 0, -1/32, 0, 0,
                       0, 0, 1/32, 0, 0, 0, 1/16, 0])
        lod_texture(helper)
        records = [dict(X=-1, Y=y, Z=z, NZ=127, COLOR=0xffff, U=u, V=v)
                   for y,z,u,v in [(0,1,0,0), (-35,256,65535,0),
                                   (35,256,0,65535)]]
        address = helper.scene.records('VERTEX', records)
        helper.scene.command('DRAW_TRI', ADDR=address, COUNT=1)
        helper.resolve()


def lod_texture(c):
    levels = [[(x*1973+y*3907+level*7391) & 65535
               for y in range(max(1,64 >> level)) for x in range(max(1,64 >> level))]
              for level in range(7)]
    address, count = c.scene.texture(levels, format=2, width=64, height=64)
    c.scene.command('TEX_LOAD', SRC=address, DST=0, BYTES=count)
    c.scene.command('SET_TEX', OFFSET=0, LOG2_W=6, LOG2_H=6, FORMAT=2,
                    LEVELS=7, SAMPLE=2)


def resolve_rows(c, width, y0, y1):
    stride = (width*2+31)//32*32
    address = c.scene.reserve(stride*y1, alignment=4096)
    c.scene.memory.write(address, bytes([0xa5])*(stride*y1))
    c.scene.command('RESOLVE', BASE=address, STRIDE=stride, X0=0, Y0=y0,
                    X1=width, Y1=y1)
    c.surfaces.append(dict(address=address, size=stride*y1,
                           width=width, height=y1, stride=stride))
