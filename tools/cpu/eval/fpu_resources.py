#!/usr/bin/env python3
# fpu_resources.py — C2-F structural estimates, not synthesis measurements.
# Design: docs/design/2026-11-27-cpu-v2-fpu.md. Clock: host.
"""Print explicit datapath and RAM estimates; excludes the C2-I integer-core baseline."""
from math import ceil, log2
from random import Random


def datapath(p):
    width = 3*p + 5
    # Two full-width variable shifts, three input normalizers, LZ trees,
    # add/sign logic, rounding, control/forward muxes, recurrence, simple ops.
    lut = (2*width*ceil(log2(width)) + 3*p*ceil(log2(p)) + 6*p
           + 3*width + p + 600 + 6*(p+4) + 6*p)
    ff = (ceil(width/36)+3)*width + 5*p + 256 + 3*(p+4) + 128
    return lut, ff


def cascade(p):
    terms = sorted((24*i+16*j, min(24, p-24*i), min(16, p-16*j))
                   for i in range(ceil(p/24)) for j in range(ceil(p/16)))
    n = len(terms)
    source_ff = sum(k*(x+y) for k, (_, x, y) in enumerate(terms))
    residue_ff = sum((terms[k+1][0]-terms[k][0])*(n-1-k) for k in range(n-1))
    return terms, source_ff, residue_ff


def verify_cascade():
    rng = Random(20261127)
    for p in (24, 53):
        terms = sorted(((24*i+16*j, 24*i, 16*j, min(24, p-24*i), min(16, p-16*j))
                        for i in range(ceil(p/24)) for j in range(ceil(p/16))),
                       key=lambda term: (term[0], term[3], term[4]))
        vectors = [(0, 0), ((1 << p)-1, (1 << p)-1), (1 << (p-1), 1 << (p-1))]
        vectors += [(rng.getrandbits(p), rng.getrandbits(p)) for _ in range(1000)]
        for a, b in vectors:
            carry = result = previous = 0
            for e, xshift, yshift, wx, wy in terms:
                delta = e-previous
                result |= (carry & ((1 << delta)-1)) << previous
                partial = ((a >> xshift) & ((1 << wx)-1)) * ((b >> yshift) & ((1 << wy)-1))
                carry = partial + (carry >> delta)
                assert carry < (1 << 47)
                previous = e
            result |= carry << previous
            assert result == a*b
    print('PASS: 2006 exact unsigned products, including the zero-shift D cascade stage')


def main():
    verify_cascade()
    f_lut, f_ff = datapath(24)
    d_lut, d_ff = datapath(53)
    for p in (24, 53):
        terms, src, residual = cascade(p)
        print(f'p={p}: weights={[t[0] for t in terms]}, APM={len(terms)}, '
              f'multiply latency={len(terms)+2}, source FF={src}, residual FF={residual}')
    print('|配置|逻辑 LUT 估算|CLM FF 估算|APM|分布式 RAM 物理位/逻辑位|LUTRAM 单元估算|')
    print('|---|---:|---:|---:|---:|---:|')
    print('|无 FPU（增量）|0|0|0|0/0|0|')
    # All APM cascade alignment stays in FF: conservative, no assumed packing.
    f_align = sum(cascade(24)[1:])
    d_align = sum(cascade(53)[1:])
    for name, width, lut, ff, apm in (
            ('F', 32, f_lut, f_ff+f_align, 2),
            ('F+D', 64, f_lut+d_lut, f_ff+d_ff+f_align+d_align, 14)):
        # 32xFLEN RF, two replicas; 16x(FLEN+5) completion RAM, three replicas.
        cells = 2*width + 3*(width+5)
        logical_bits = 2*32*width + 3*16*(width+5)
        print(f'|{name}|{lut}|{ff}|{apm}|{cells*64}/{logical_bits}|{cells}|')
    print(f'额外完整 FADD 管线（split）≈ LUT {datapath(24)[0]//3}, '
          f'FF {datapath(24)[1]//3}；共享 FP64（wide）≈ LUT {d_lut}, '
          f'FF {d_ff+d_align}, APM 12。')


if __name__ == '__main__':
    main()
