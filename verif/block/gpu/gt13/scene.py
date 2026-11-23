"""GT-13: gpu-spec 2.8; x modulo four, widths 1–64, flips and clipped edges."""
from scene_support import Case


def build(c, rng):
    for flip in range(4):
        for mod in range(4):
            run = c if flip == mod == 0 else Case()
            if run is not c:
                c.runs.append(run)
            run.ready()
            run.texture(patterned=True)
            for width in range(1,65):
                # Offset target brings its physical right/bottom edge to screen coordinate 64.
                if width % 2:
                    run.target(TGT_X0=-576, TGT_Y0=-116)
                    run.clear()
                    run.target(TGT_X0=-576, TGT_Y0=-116,
                               SC_X0=3, SC_Y0=5, SC_X1=68, SC_Y1=68)
                else:
                    run.target()
                    run.clear()
                    run.target(SC_X0=3, SC_Y0=5, SC_X1=61, SC_Y1=59)
                x = [-4+mod, 60+mod, 12+mod][width % 3]
                y = [-3,60,12][width % 3]
                run.quad(X=x, Y=y, W=width, H=rng.randrange(1,65), U0=7, V0=6,
                         FLIP_H=flip & 1, FLIP_V=flip >> 1)
                # Return to a target whose contents were initialized at these physical pixels.
                if width % 2:
                    run.target(TGT_X0=-576, TGT_Y0=-116)
                else:
                    run.target()
                run.resolve()
