#!/usr/bin/env python3
"""G-P03 integer reference: independent N48, full products and canonical relocation."""
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/gpu/study'))
from m5_setup import corpus
from m6_sfu import RCP


def rounded_shift(value, amount):
    if amount <= 0:
        return value << -amount
    magnitude = (abs(value) + (1 << (amount-1))) >> amount
    return -magnitude if value < 0 else magnitude


def n48(value, exponent):
    if not value:
        return 0, 0
    amount = abs(value).bit_length()-47
    mantissa = rounded_shift(value, amount)
    if abs(mantissa) >= 1 << 47:
        amount += 1
        mantissa = rounded_shift(value, amount)
    return mantissa, exponent+amount


class Reference:
    def __init__(self):
        self.norms = []
        self.products = []
        self.relocations = []

    def normal(self, value, exponent=0):
        result = n48(value, exponent)
        assert -(1 << 81) <= value < 1 << 81
        assert -512 <= result[1] < 512
        self.norms.append((value, exponent, *result))
        return result

    def product(self, a, b):
        assert -(1 << 48) <= a < 1 << 48
        assert -(1 << 32) <= b < 1 << 32
        self.products.append((a, b, a*b))
        return a*b

    def times(self, a, b):
        return self.normal(self.product(a[0], b[0]), a[1]+b[1])

    def plus(self, a, b):
        if not a[0]:
            return b
        if not b[0]:
            return a
        exponent = max(a[1], b[1])-3
        return self.normal(rounded_shift(a[0], exponent-a[1]) +
                           rounded_shift(b[0], exponent-b[1]), exponent)

    def source(self, vertices, values):
        a, b, c = vertices
        dx1, dy1 = b[0]-a[0], b[1]-a[1]
        dx2, dy2 = c[0]-a[0], c[1]-a[1]
        area = self.product(dx1, dy2)-self.product(dx2, dy1)
        assert area > 0
        k = area.bit_length()-1
        m = rounded_shift(area, k-31)
        if m == 1 << 32:
            m >>= 1
            k += 1
        y = round(RCP[(m-(1 << 31)) >> 25]*(1 << 31))
        for _ in range(2):
            y = rounded_shift(self.product(y, (2 << 31)-
                              rounded_shift(self.product(m, y), 31)), 31)
        inv = y, -31-k
        attrs = [self.normal(v) for v in values]
        exponent = max(v[1] for v in attrs)
        v0, v1, v2 = [rounded_shift(v[0], exponent-v[1]) for v in attrs]
        d1, d2 = v1-v0, v2-v0
        nx = self.product(d1, dy2)-self.product(d2, dy1)
        ny = self.product(d2, dx1)-self.product(d1, dx2)
        gx, gy = [self.times(self.normal(n, exponent+4), inv) for n in (nx, ny)]
        anchor = tuple(min(p[i] for p in vertices)//1024*64 for i in (0, 1))
        localx = self.times(gx, (16*anchor[0]+8-a[0], -4))
        localy = self.times(gy, (16*anchor[1]+8-a[1], -4))
        start = self.plus((v0, exponent), self.plus(localx, localy))
        common = max(e+abs(m).bit_length() for m, e in (start, gx, gy))-47
        fields = tuple(rounded_shift(m, common-e) for m, e in (start, gx, gy))
        if max(map(abs, fields)) >= 1 << 47:
            common += 1
            fields = tuple(rounded_shift(m, common-e) for m, e in (start, gx, gy))
        return fields, common

    def relocate(self, fields, x, y):
        s, gx, gy = fields
        result = s+64*x*gx+64*y*gy
        assert -(1 << 59) <= result < 1 << 59
        self.relocations.append((*fields, x, y, result))
        return result


def vectors(destination):
    ref = Reference()
    boundary_checks = 0
    for _, vertices in corpus():
        for values in ([1000, 64000, 24000], [2**30, 2**29, 2**28]):
            fields, _ = ref.source(vertices, values)
            for offset in (1, 2, 3, 4, 8):
                left = ref.relocate(fields, offset-1, 0)
                right = ref.relocate(fields, offset, 0)
                below = ref.relocate(fields, offset, 1)
                assert left+64*fields[1] == right
                assert right+64*fields[2] == below
                # Direct helper/boundary pixels: relocation is an exact integer identity.
                for dx in (-1, 0, 1):
                    assert right+dx*fields[1] == fields[0]+(64*offset+dx)*fields[1]
                boundary_checks += 2
    assert boundary_checks == 780
    # Every leading position, sign, tie and renormalizing carry, including zero/min82.
    ref.normal(0)
    ref.normal(-(1 << 81))
    for bit in range(81):
        for delta in (-1, 0, 1):
            for sign in (-1, 1):
                value = sign*((1 << bit)+delta)
                if -(1 << 81) <= value < 1 << 81:
                    ref.normal(value, 11)
    for bit in range(1, 35):
        for sign in (-1, 1):
            ref.normal(sign*((1 << (47+bit))-(1 << (bit-1))), -100)
    edges_a = [-(1 << 48), -(1 << 48)+1, -1, 0, 1, (1 << 48)-1]
    edges_b = [-(1 << 32), -(1 << 32)+1, -1, 0, 1, (1 << 32)-1]
    for a in edges_a:
        for b in edges_b:
            ref.product(a, b)
    rng = random.Random(20261128)
    for _ in range(2048):
        ref.normal(rng.randrange(-(1 << 81), 1 << 81), rng.randrange(-400, 400))
        ref.product(rng.randrange(-(1 << 48), 1 << 48),
                    rng.randrange(-(1 << 32), 1 << 32))
        fields = tuple(rng.randrange(-(1 << 47), 1 << 47) for _ in range(3))
        ref.relocate(fields, rng.randrange(20), rng.randrange(12))
    for x in range(20):
        for y in range(12):
            ref.relocate(((1 << 47)-1, -(1 << 47), (1 << 47)-1), x, y)
    widths = [82, 10, 48, 10, 49, 33, 82, 48, 48, 48, 5, 4, 60]
    count = max(map(len, (ref.norms, ref.products, ref.relocations)))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('w') as output:
        for i in range(count):
            row = (*ref.norms[i % len(ref.norms)], *ref.products[i % len(ref.products)],
                   *ref.relocations[i % len(ref.relocations)])
            output.write(' '.join(f'{v & ((1 << w)-1):x}' for v, w in zip(row, widths))+'\n')
    print(f'setup vectors={count}, triangles=39, integer boundary identities=780')
    return count


if __name__ == '__main__':
    vectors(ROOT / 'build/gpu2/setup/vectors.txt')
