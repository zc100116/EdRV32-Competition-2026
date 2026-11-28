#!/usr/bin/env python3
# File: check.py
# Spec: fpu-testplan FV02/FV04-FV09, FT01; fpu-spec 2.1-2.3.
# Description: Assert hand-computed bit patterns without host floating point.
# Clock: host only.
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools/fpu'))
from reference import Reference, box, instruction


def check():
    reference = Reference()
    count = 0

    def expect(op, width, flen, inputs, result, flags=0, dest=0, rm=0, integer=0):
        nonlocal count
        a, b, c = (list(inputs) + [0, 0, 0])[:3]
        actual = reference.evaluate(op, width, flen, a, b, c, integer, rm)
        wanted = (result, flags, dest)
        assert actual == wanted, (op, width, flen, rm, inputs, wanted, actual)
        count += 1

    for flen in [32, 64]:
        for width in ([32] if flen == 32 else [32, 64]):
            s = width == 32
            sign = 1 << (width - 1)
            one = 0x3f800000 if s else 0x3ff0000000000000
            two = 0x40000000 if s else 0x4000000000000000
            inf = 0x7f800000 if s else 0x7ff0000000000000
            qnan = 0x7fc12345 if s else 0x7ff8123456789abc
            snan = inf | 1
            canonical = 0x7fc00000 if s else 0x7ff8000000000000
            normal = 0x800000 if s else 0x10000000000000
            def b(x):
                return box(x, width, flen)
            for rm in range(5):
                expect('add', width, flen, [b(one), b(one)], b(two), rm=rm)
                expect('mul', width, flen, [b(1), b(one)], b(1), rm=rm)
                expect('add', width, flen, [b(normal - 1), b(1)], b(normal), rm=rm)
                expect('to_w', width, flen, [b(inf)], 0x7fffffff, 16, 1, rm)
                expect('to_w', width, flen, [b(inf | sign)], 0x80000000, 16, 1, rm)
                expect('to_w', width, flen, [b(qnan)], 0x7fffffff, 16, 1, rm)
                expect('to_wu', width, flen, [b(qnan)], 0xffffffff, 16, 1, rm)
                expect('to_wu', width, flen, [b(one | sign)], 0, 16, 1, rm)
                expect('from_w', width, flen, [], b(one | sign), rm=rm, integer=0xffffffff)
                # Half an ULP above one; RMM/RUP round up, all other modes down.
                half_ulp = 0x33800000 if s else 0x3ca0000000000000
                expect('add', width, flen, [b(one), b(half_ulp)],
                       b(one + int(rm in [3, 4])), 1, rm=rm)
                expect('add', width, flen, [b(one | sign), b(half_ulp | sign)],
                       b((one + int(rm in [2, 4])) | sign), 1, rm=rm)
                # Tiny halfway result rounds to zero or minimum subnormal.
                half = 0x3f000000 if s else 0x3fe0000000000000
                expect('mul', width, flen, [b(1), b(half)], b(int(rm in [3, 4])), 3, rm=rm)
            maxfinite = inf - 1
            expect('mul', width, flen, [b(maxfinite), b(two)], b(inf), 5)
            expect('madd', width, flen, [b(maxfinite), b(two), b(maxfinite | sign)],
                   b(maxfinite))
            expect('add', width, flen, [b(qnan), b(one)], b(canonical))
            expect('add', width, flen, [b(snan), b(one)], b(canonical), 16)
            expect('madd', width, flen, [b(0), b(inf), b(qnan)], b(canonical), 16)
            expect('mul', width, flen, [b(0), b(inf)], b(canonical), 16)
            expect('div', width, flen, [b(one), b(0)], b(inf), 8)
            expect('div', width, flen, [b(0), b(0)], b(canonical), 16)
            expect('sqrt', width, flen, [b(sign)], b(sign))
            expect('sqrt', width, flen, [b(one | sign)], b(canonical), 16)
            expect('min', width, flen, [b(qnan), b(one)], b(one))
            expect('min', width, flen, [b(snan), b(one)], b(one), 16)
            expect('min', width, flen, [b(0), b(sign)], b(sign))
            expect('max', width, flen, [b(sign), b(0)], b(0))
            expect('eq', width, flen, [b(qnan), b(one)], 0, dest=1)
            expect('eq', width, flen, [b(snan), b(one)], 0, 16, 1)
            for op in ['lt', 'le']:
                expect(op, width, flen, [b(qnan), b(one)], 0, 16, 1)
            expect('sgnj', width, flen, [b(qnan), b(sign)], b(qnan | sign))
            expect('sgnjn', width, flen, [b(snan), b(0)], b(snan | sign))
            expect('sgnjx', width, flen, [b(snan | sign), b(sign)], b(snan))
            classes = [inf | sign, one | sign, sign | 1, sign, 0, 1, one, inf, snan, qnan]
            for index, value in enumerate(classes):
                expect('class', width, flen, [b(value)], 1 << index, dest=1)
            # (1+2^-p)(1-2^-p)-1 = -2^(-2p), exact and fused.
            fused = 0xa8800000 if s else 0xb970000000000000
            for op in ['madd', 'msub', 'nmadd', 'nmsub']:
                a, c = one + 1, one | sign
                if op in ['nmadd', 'nmsub']:
                    a ^= sign
                if op in ['msub', 'nmadd']:
                    c ^= sign
                expect(op, width, flen, [b(a), b(one - 2), b(c)], b(fused))
    # After-rounding tininess: a quarter-subnormal ULP below min S normal.
    expect('to_s', 64, 64, [0x380ffffff0000000], 0xffffffff00800000, 1)
    expect('to_w', 32, 32, [0x4f000000], 0x7fffffff, 16, 1)
    expect('to_w', 32, 32, [0xcf000000], 0x80000000, 0, 1)
    expect('to_wu', 32, 32, [0x4f800000], 0xffffffff, 16, 1)
    expect('mv_x_w', 32, 64, [0x123456787f812345], 0x7f812345, dest=1)
    expect('store', 32, 64, [0x123456787f812345], 0x7f812345)
    expect('mv_w_x', 32, 64, [], 0xffffffff7f812345, integer=0x7f812345)
    expect('load', 32, 64, [0x7f812345], 0xffffffff7f812345)
    expect('load', 64, 64, [0x123456787f812345], 0x123456787f812345)
    expect('store', 64, 64, [0x123456787f812345], 0x123456787f812345)
    expect('add', 32, 64, [0x3f800000, 0xffffffff3f800000], 0xffffffff7fc00000)
    expect('class', 32, 64, [0x7f800001], 512, dest=1)
    expect('sgnj', 32, 64, [0x3f800000, 0xffffffff80000000], 0xffffffffffc00000)
    expect('to_s', 64, 64, [0x3ff0000000000000], 0xffffffff3f800000)
    expect('to_d', 32, 64, [0xffffffff3f800000], 0x3ff0000000000000)
    expect('to_d', 32, 64, [0x3f800000], 0x7ff8000000000000)
    assert instruction('madd', 32, 0) == 0x18208043
    print(f'PASS {count} hand-computed RISC-V reference assertions')


if __name__ == '__main__':
    check()
