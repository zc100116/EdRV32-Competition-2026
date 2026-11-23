"""GT-06: gpu-spec 2.5; seeded shared edges/vertices and degenerate triangles."""
import struct


def build(c, rng):
    c.ready()
    c.texture(0x0821)
    c.pixel(BL_FS=1, BL_FD=1, BL_OP=0)
    # Integer object coordinates map exactly to pixel coordinates in a 64-pixel viewport.
    c.matrix([1/32, 0, 0, -1, 0, -1/32, 0, 1, 0, 0, 0, .5, 0, 0, 0, 1])
    grid = [[(4+x*7 + (rng.randrange(-2, 3) if 0 < x < 8 else 0),
              4+y*7 + (rng.randrange(-2, 3) if 0 < y < 8 else 0))
             for x in range(9)] for y in range(9)]
    for y in range(8):
        for x in range(8):
            a, b, d, e = grid[y][x], grid[y][x+1], grid[y+1][x], grid[y+1][x+1]
            pairs = [(a, b, e), (a, e, d)] if rng.randrange(2) else [(a, b, d), (b, e, d)]
            for points in pairs:
                c.triangles(points if rng.randrange(2) else points[::-1])
    c.triangles([(8, 8), (8, 8), (8, 8), (12, 12), (20, 20), (28, 28)])
    c.resolve()
    c.checks.append(lambda gpu: check(gpu, c))


def check(gpu, case):
    surface = case.surfaces[0]
    words = struct.unpack('<4096H', gpu.memory.read(surface['address'], surface['size']))
    for y in range(64):
        for x in range(64):
            expected = 0x0821 if 4 <= x < 60 and 4 <= y < 60 else 0
            assert words[y*64+x] == expected, (x, y, expected, words[y*64+x])
    assert gpu.regs['PERF[4]'] == 56*56
