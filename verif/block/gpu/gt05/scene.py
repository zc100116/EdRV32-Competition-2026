"""GT-05: gpu-spec 2.4; both windings under all specified cull modes."""


def build(c, rng):
    c.ready()
    for cull in range(3):
        for points in [[(-1, -1), (1, -1), (0, 1)], [(0, 1), (1, -1), (-1, -1)]]:
            c.clear()
            c.pixel(CULL=cull)
            c.triangles(points)
            c.resolve()
