#!/usr/bin/env python3
"""Boundary cross products, fused counterexamples, and deterministic random input."""
import argparse
import itertools
import random
from pathlib import Path
from model import fma


def directed():
    # All signs/classes in each source; zeros, extrema, normal/subnormal boundaries,
    # quiet/signaling NaN payloads and infinities are crossed independently.
    values = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x807fffff,
              0x00800000, 0x80800000, 0x3f800000, 0xbf800000,
              0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000,
              0x7fc00001, 0xffcabcde, 0x7f800001, 0xff812345]
    yield from itertools.product(values, repeat=3)
    cases = [
        (0x3f800001, 0x3f7ffffe, 0xbf800000),  # FV06: exact -2^-46
        (0x7f7fffff, 0x40000000, 0xff7fffff),  # overflowed product cancels
        (0x3f800000, 0x3f800000, 0xbf800000),  # exact cancellation
        (0x3f800000, 0x33800000, 0x3f800000),  # half-ULP, even
        (0x3f800000, 0x33800000, 0x3f800001),  # half-ULP, odd
        (0x00800000, 0x3f7fffff, 0),          # tiny rounds to min-normal
        (1, 0x3f000000, 0),                   # half minimum subnormal
        (0x80000001, 0x3f000000, 0),
    ]
    yield from cases
    # Neighbours of ties at normal, subnormal, overflow and cancellation edges.
    for a, b, c in cases:
        for da, db, dc in itertools.product((-1, 0, 1), repeat=3):
            yield (a + da) & 0xffffffff, (b + db) & 0xffffffff, (c + dc) & 0xffffffff


def random_cases(count):
    rng = random.Random(0xF32F09)
    for i in range(count):
        a, b, c = (rng.getrandbits(32) for _ in range(3))
        if i % 4 == 0:
            # Close product and addend exponents exercise deep cancellation.
            ea, eb = rng.randrange(1, 254), rng.randrange(1, 254)
            ec = max(0, min(254, ea + eb - 127 + rng.randrange(-3, 4)))
            a = (a & 0x807fffff) | (ea << 23)
            b = (b & 0x807fffff) | (eb << 23)
            c = (c & 0x807fffff) | (ec << 23)
        elif i % 4 == 1:
            # Densely exercise gradual underflow and subnormal operands.
            a &= 0x80ffffff
            b = (b & 0x807fffff) | (rng.randrange(0, 150) << 23)
            c &= 0x80ffffff
        yield a, b, c, rng.randrange(4), rng.randrange(5)


def generate(path, count):
    total = 0
    with path.open('w') as out:
        cases = itertools.chain(((*abc, op, rm) for abc in directed()
                                 for op in range(4) for rm in range(5)), random_cases(count))
        for a, b, c, op, rm in cases:
            result, flags = fma(a, b, c, op, rm)
            out.write(f'{a:08x} {b:08x} {c:08x} {op:x} {rm:x} {result:08x} {flags:02x}\n')
            total += 1
    print(f'Generated {total} exact Fraction reference vectors', flush=True)
    return total


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--random', type=int, default=10000)
    args = parser.parse_args()
    generate(args.output, args.random)
