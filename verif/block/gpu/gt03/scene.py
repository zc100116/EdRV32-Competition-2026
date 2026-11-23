"""GT-03: gpu-spec 2.4; forward, backward, perpendicular and saturated lighting."""


def build(c, rng):
    c.ready()
    for normal in [(0, 0, 127), (0, 0, -128), (127, 0, 0)]:
        for ambient, directional in [(0, 0xffffff), (0x808080, 0xffffff),
                                     (0xffffff, 0xffffff)]:
            c.light(AMB_RGB=ambient, DIR_RGB=directional)
            c.triangles([(-1, -1), (1, -1), (0, 1)],
                        NX=normal[0], NY=normal[1], NZ=normal[2])
            c.resolve()
    for _ in range(12):
        c.light(AMB_RGB=rng.randrange(1 << 24), DIR_RGB=rng.randrange(1 << 24))
        c.triangles([(-1, -1), (1, -1), (0, 1)], NX=rng.randrange(-128, 128),
                    NY=rng.randrange(-128, 128), NZ=rng.randrange(-128, 128),
                    COLOR=rng.randrange(65536))
        c.resolve()
