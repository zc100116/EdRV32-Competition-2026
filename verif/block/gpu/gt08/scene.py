"""GT-08: gpu-spec 2.7; depth functions, write switch, equality and color probes."""


def build(c, rng):
    c.ready()
    for function in [0, 1]:
        for write in [0, 1]:
            c.clear(depth=100)
            c.pixel(DEPTH_FUNC=function, DEPTH_WRITE=write)
            # Separate tiles make equal/near/far fragments observable together.
            for x, depth in [(0, 99), (16, 100), (32, 101)]:
                c.texture(0xf800)
                c.quad(X=x, Y=0, W=16, H=16, DEPTH=depth)
            c.resolve()
            # Probe each written depth at d-1, d and d+1; probe writes never alter depth.
            for probe in [98, 99, 100, 101, 102]:
                c.pixel(DEPTH_FUNC=1, DEPTH_WRITE=0)
                c.texture(0x001f)
                c.quad(X=0, Y=0, W=48, H=16)
                c.pixel(DEPTH_FUNC=0, DEPTH_WRITE=0)
                c.texture(0x07e0)
                c.quad(X=0, Y=0, W=48, H=16, DEPTH=probe)
                c.resolve()
