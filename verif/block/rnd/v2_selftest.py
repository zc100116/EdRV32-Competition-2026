#!/usr/bin/env python3
# File: v2_selftest.py
# Spec: rnd 2.2, 2.3, 2.6; rnd-testplan 4, RN-21–27.
# Description: Hand results and direct Cartesian/Fraction crosschecks for new arithmetic.
# Clock domain: host.
from dataclasses import replace
from fractions import Fraction
import random

from rnd_ref import (Command, Q, affine_sample, blit, box_shadow, circle_value, execute,
                     geometry_coverage, geometry_inside, linear8, load, store, xy)
from v2_vectors import affine, circle, line, put_parameters, triangle


def selftest():
    rng = random.Random(0x5632)
    # q0 signed48 decoding, ignored high16, and exact delta formula vs Cartesian distance.
    for _ in range(300):
        rect = (rng.randrange(-30000, 30000), rng.randrange(-30000, 30000), 0, 0)
        cx, cy, radius = (rng.randrange(-200000, 200000) for _ in range(3))
        words = circle(rect, cx, cy, abs(radius))
        words = (words[0], words[1] | 0xabcd0000, *words[2:])
        for a, b in ((0, 0), (2, 6), (3, 3), (128, -72)):
            want = (rect[0] * 8 + 1 + a - cx) ** 2
            want += (rect[1] * 8 + 1 + b - cy) ** 2 - radius ** 2
            assert circle_value(words, a, b) == want, ('q', words, a, b, want)
    # Sub-Q16 signed edge samples must survive until strict/non-strict comparison.
    for e0, ex, ey in ((0, 1, -1), (-1, 7, -3), (0x7fffffff, -17, 3)):
        for a in range(8):
            for b in range(8):
                want = Fraction(e0) + Fraction(a, 8) * ex + Fraction(b, 8) * ey
                assert linear8((e0, ex, ey), a, b) == want * 8
    inclusive = Command(9, flags=2 | 4 | 8)
    exclusive = replace(inclusive, flags=0)
    p = [0, 1, -1, 65536, 0, 0, 65536, 0, 0]
    assert geometry_inside(inclusive, p, 1, 1)
    assert not geometry_inside(exclusive, p, 1, 1)
    assert geometry_inside(exclusive, p, 3, 1)
    assert not geometry_inside(inclusive, p, 1, 3)
    # Two top-left triangles partition every subpoint of the 2x2 square exactly once.
    rect = (0, 0, 1, 1)
    a, ap = triangle(rect, ((0, 0), (2, 0), (2, 2)))
    b, bp = triangle(rect, ((0, 0), (2, 2), (0, 2)))
    for y in (1, 3, 5, 7, 9, 11, 13, 15):
        for x in (1, 3, 5, 7, 9, 11, 13, 15):
            assert geometry_inside(a, ap, x, y) + geometry_inside(b, bp, x, y) == 1
    assert geometry_coverage(a, ap, 0, 0) == 159  # 10/16 samples including diagonal.
    assert geometry_coverage(b, bp, 0, 0) == 96
    # Zero length with radius 1 at pixel center: all sixteen samples inside, caps union once.
    c, cp = line((0, 0, 0, 0), (4, 4), (4, 4), 8, caps=3)
    assert geometry_coverage(c, cp, 0, 0) == 255
    # Full ARC ignores both angular halfplanes and all cap contributions.
    arc = Command(11, rect=(0, 0, 0, 0), flags=1 | 6 | 16 | 32)
    arc_p = list(circle((0, 0, 0, 0), 4, 4, 8)) * 4 + [-1, 0, 0] * 2
    assert geometry_coverage(arc, arc_p, 0, 0) == 255
    arc_p[:4] = circle((0, 0, 0, 0), 1000, 1000, 8)
    assert geometry_coverage(arc, arc_p, 0, 0) == 0
    memory = bytearray(0x80000)
    # MASK direct write: hidden RGB disappears at alpha zero and survives at alpha one.
    for alpha in (0, 1, 128, 255):
        for keep in (0, 1):
            c = Command(12, rect=(0, 0, 1, 0), clip=(0, 0, 1, 0), flags=keep,
                        args=(0, xy(0, 0), xy(0, 0), 0, 0, 0, 0, 0))
            for x in range(2):
                store(memory, 0x10000 + x * 4, 4, (alpha << 24) | 0x123456)
            execute(memory, [c])
            want = (alpha << 24) | 0x123456 if alpha else 0
            assert load(memory, 0x10000, 4) == want
            assert load(memory, 0x10004, 4) == (want if keep else 0)
    # ROUND_CLIP and CUTOUT hand examples exercise command decoding/writeback.
    memory[:] = bytes(len(memory))
    for y in range(4):
        for x in range(4):
            store(memory, 0x20000 + 16 * y + 4 * x, 4, 0xff123456)
    put_parameters(memory, 0x48000, [0, xy(0, 0), xy(3, 3)], 64)
    c = blit(src_base=0x20000, src_stride=16, src_fmt=1, palette=0x48000,
             clip_radius=1, flags=128, rect=(0, 0, 3, 3), clip=(0, 0, 3, 3), opa=255)
    execute(memory, [c])
    assert load(memory, 0x10000, 4) == 0xd0123456
    c = box_shadow(temp_base=0x60000, blur=0, flags=1, bg=(0, 0, 0, 0),
                   rect=(0, 0, 1, 0), clip=(0, 0, 1, 0), color=0xabcdef, opa=255)
    store(memory, 0x10000, 4, 0xff778899)
    execute(memory, [c])
    assert load(memory, 0x10000, 4) == 0xff778899
    assert load(memory, 0x10004, 4) == 0xffabcdef
    # Transparent saturated RGB cannot bleed into the half-way opaque red sample.
    store(memory, 0x20000, 4, 0xffff0000)
    store(memory, 0x20004, 4, 0x0000ffff)
    c = affine(src_base=0x20000, src_stride=8, source_size=(2, 1), flags=1,
               rect=(0, 0, 0, 0))
    p = (65536, 32768, 0, 0, 0, 0)
    assert affine_sample(memory, c, p, 0, 0) == (128, 255, 0, 0)
    assert affine_sample(memory, c, (-1, 32768, 0, 0, 0, 0), 0, 0) == (127, 255, 0, 0)
    nn = replace(c, flags=0)
    assert affine_sample(memory, nn, (-1, 0, 0, 0, 0, 0), 0, 0) == (0, 0, 0, 0)
    # Every f/g corner and alpha=0/1/255 checks premultiply, rounding, Q and saturation.
    for alpha in (0, 1, 255):
        for k, value in enumerate((0xff0000, 0x00ff00, 0x0000ff, 0xffffff)):
            store(memory, 0x20000 + (k // 2) * 8 + (k % 2) * 4, 4,
                  (alpha << 24) | value)
        c = replace(c, args=(c.args[0], 8, xy(2, 2), *c.args[3:]))
        for f in (0, 1, 127, 255):
            for g in (0, 1, 127, 255):
                weights = ((256-f)*(256-g), f*(256-g), (256-f)*g, f*g)
                channels = ((alpha, 0, 0, alpha), (0, alpha, 0, alpha), (0, 0, alpha, alpha))
                premul = [(sum(w * v for w, v in zip(weights, ch)) + 32768) // 65536
                           for ch in channels]
                want = ((alpha,) + tuple(min(255, (v * Q[alpha] + 32768) // 65536)
                                        for v in premul)) if alpha else (0, 0, 0, 0)
                p = (32768 + f * 256, 32768 + g * 256, 0, 0, 0, 0)
                assert affine_sample(memory, c, p, 0, 0) == want, (alpha, f, g, want)
    # Absolute signed48 accumulation crosses 32-bit and returns, without intermediate wrap.
    c = replace(c, rect=(-32768, -32768, 1, 1))
    p = (32768, 32768, 0x7fffffff, 0, -0x7fffffff, 0)
    assert affine_sample(memory, c, p, 0, 0)[0] == 255
    assert affine_sample(memory, c, p, 2, 0) == (0, 0, 0, 0)
    # Empty new commands cannot fetch an invalid parameter pointer.
    for op in (9, 10, 11, 13):
        c = Command(op, rect=(1, 0, 0, 0), args=(0xffffffff,) * 8)
        assert execute(memory, [c]).completed == 1
    print('PASS v2 formula selftest: Cartesian circles=1200, exact edges=192, '
          'shared samples=64, MASK=8, bilinear f/g/alpha=48, signed48, empty parameters')
