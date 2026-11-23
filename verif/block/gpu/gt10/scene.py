"""GT-10: gpu-spec 2.7; all 10x10 factors and 5 blend ops, alpha limits and randoms."""


def build(c, rng):
    c.ready()
    combinations = [(fs, fd, op, alpha, constant, source, dest)
                    for fs in range(10) for fd in range(10) for op in range(5)
                    for alpha, constant, source, dest in
                    [(0, 0, 0xffff, 0xffff), (255, 255, 0xffff, 0xffff),
                     (127, 97, 0x8410, 0xf81f), (193, 128, 0x07ff, 0x780f)]]
    combinations += [(rng.randrange(10), rng.randrange(10), rng.randrange(5),
                      rng.randrange(256), rng.randrange(256), rng.randrange(65536),
                      rng.randrange(65536)) for _ in range(128)]
    for index, (fs, fd, op, alpha, constant, source, dest) in enumerate(combinations):
        x, y = index % 64, index//64
        c.target(SC_X0=x, SC_Y0=y, SC_X1=x+1, SC_Y1=y+1)
        c.scene.command('CLEAR', COLOR=dest, EN_COLOR=1)
        c.texture(source)
        c.pixel(BL_FS=fs, BL_FD=fd, BL_OP=op, BL_CONST_A=constant)
        c.quad(X=x, Y=y, W=1, H=1, ALPHA=alpha)
    c.target()
    c.resolve()
