"""GT-02: gpu-spec 2.4, 2.12; seeded transforms, saturation and offset viewport."""


def build(c, rng):
    c.ready(VP_X0=7, VP_Y0=5, VP_W=48, VP_H=40)
    for index in range(18):
        matrix = [rng.uniform(.02, .12), 0, 0, rng.uniform(-.5, .5),
                  0, rng.uniform(.02, .12), 0, rng.uniform(-.5, .5),
                  0, 0, .03, .2, 0, 0, rng.uniform(.01, .07), 1]
        c.matrix(matrix)
        c.triangles([(rng.randrange(-12, 13), rng.randrange(-12, 13), rng.randrange(1, 9))
                     for _ in range(3)])
    # Maximum matrix products saturate the signed 40-bit clip coordinates.
    c.matrix([32767, 32767, 32767, 32767,
              -32768, -32768, -32768, -32768,
              0, 0, 0, 1, 0, 0, 0, 1])
    c.triangles([(32767, 32767, 32767), (32766, 32767, 32767), (32767, 32766, 32767)])
    c.resolve()
