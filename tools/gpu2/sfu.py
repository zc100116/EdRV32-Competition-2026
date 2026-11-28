#!/usr/bin/env python3
"""GPU v2 §2.4 M-6 small SFU using integer FP32 operations at every node."""
import math
import random
from tools.gpu2 import fp32 as f

RCP = tuple(f.bits(1 / (1 + (i + .5) / 64)) for i in range(64))
RSQ = tuple(f.bits(1 / math.sqrt(1 + 3 * (i + .5) / 64)) for i in range(64))
LOG = tuple(f.bits(math.log2(.75 + i / 64)) for i in range(49))
INV = tuple(f.bits(1 / (.75 + i / 64)) for i in range(49))
EXP = tuple(f.bits(2 ** (i / 64)) for i in range(64))
LATENCY = (47, 68, 88, 78)
SLOTS = ((4, 0), (14, 0), (24, 1), (34, 1),
         (45, 0), (55, 0), (65, 1), (75, 1))
COUNTS = (4, 6, 8, 7)


def scale(word, power):
    if f.inf(word) or f.nan(word):
        return word
    mantissa, exponent = f.finite(word)
    return f.pack(mantissa, exponent + power, word >> 31)


def sfu(op, word):
    x = f.value(word)
    if op in (0, 1, 2):
        if x == 0:
            return ((word & 0x80000000) | 0x7f800000) if op == 0 else (
                0x7f800000 if op == 1 else 0xff800000)
        m, e = math.frexp(abs(x) if op == 0 else x)
    if op == 0:
        m, e = m * 2, e - 1
        y = RCP[int((m - 1) * 64)]
        negative_m = f.bits(-m)
        for _ in range(2):
            y = f.fma(y, f.fma(negative_m, y, f.bits(1)), y)
        return scale(y, -e) | (word & 0x80000000)
    if op == 1:
        m, e = m * 2, e - 1
        if e & 1:
            m, e = m * 2, e - 1
        y = RSQ[int((m - 1) * 64 / 3)]
        for _ in range(2):
            y = f.mul(y, f.fma(f.bits(-.5 * m), f.mul(y, y), f.bits(1.5)))
        return scale(y, -e // 2)
    if op == 2:
        if m < .75:
            m, e = m * 2, e - 1
        i = round((m - .75) * 64)
        r = f.mul(f.add(f.bits(m), f.bits(-(.75 + i / 64))), INV[i])
        p = f.bits(1 / 5)
        for c in (-1 / 4, 1 / 3, -.5, 1):
            p = f.fma(r, p, f.bits(c))
        return f.fma(f.mul(r, p), f.bits(1 / math.log(2)),
                     f.add(f.bits(e), LOG[i]))
    if op == 3:
        if word == 0xff800000:
            return 0
        e = math.floor(x)
        i = int((x - e) * 64)
        # M6 multiplies the exact residual before FP32 rounding. For a small
        # negative x, x+1/64 may need 25+ bits; an FMA preserves that residual
        # without a wider multiplier or an extra arithmetic reservation.
        r = (f.fma(word, f.bits(math.log(2)), f.bits(math.log(2) / 64))
             if -1 / 64 < x < 0 else
             f.mul(f.bits(x - e - i / 64), f.bits(math.log(2))))
        p = f.bits(1 / 120)
        for c in (1 / 24, 1 / 6, .5, 1, 1):
            p = f.fma(r, p, f.bits(c))
        return scale(f.mul(EXP[i], p), e)
    raise ValueError(op)


def reservation():
    occupied = set()
    rng = random.Random(20261127)
    for request in range(512):
        op = rng.randrange(4)
        for offset, engine in SLOTS[:COUNTS[op]]:
            key = (4 * request + offset, engine)
            assert key not in occupied, key
            occupied.add(key)
    return len(occupied)



if __name__ == '__main__':
    print(f'PASS 512 mixed II4 requests, {reservation()} arithmetic reservations')
