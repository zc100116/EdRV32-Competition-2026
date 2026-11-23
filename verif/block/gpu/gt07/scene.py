"""GT-07: gpu-spec 2.5; ground/wall texture perspective with large W ratios."""


def build(c, rng):
    c.ready()
    c.texture(patterned=True)
    for ratio in [2, 8, 32, 128]:
        for wall in [False, True]:
            c.clear()
            c.matrix([1/16, 0, 0, 0, 0, 1/16, 0, 0, 0, 0, 1/32, 0,
                      0, 0, 1/16, 1/16])
            points = [(-1, -1, 0), (1, -1, 0), (ratio, ratio, ratio-1),
                      (-1, -1, 0), (ratio, ratio, ratio-1), (-ratio, ratio, ratio-1)]
            if wall:
                points = [(y, x, z) for x, y, z in points]
            c.triangles(points)
            c.resolve()
