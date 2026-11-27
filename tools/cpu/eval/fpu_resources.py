#!/usr/bin/env python3
# fpu_resources.py — C2-F structural estimates, not synthesis measurements.
# Design: docs/design/2026-11-27-cpu-v2-fpu.md. Clock: host.
"""Print explicit datapath and RAM estimates; excludes the C2-I integer-core baseline."""
from math import ceil, log2
from random import Random
from v2_estimates import estimate


def datapath(p):
    width = 3*p + 5
    # Two full-width variable shifts, three input normalizers, LZ trees,
    # add/sign logic, rounding, control/forward muxes, recurrence, simple ops.
    lut = (2*width*ceil(log2(width)) + 3*p*ceil(log2(p)) + 6*p
           + 3*width + p + 600 + 6*(p+4) + 6*p)
    ff = (ceil(width/84)+2)*width + 5*p + 256 + 3*(p+4) + 128
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


def resources(fmt, depth=8, reads=2, scheme='bypass', queue_forward=True):
    """Increment from integer-only four-entry FF queue; RAM LUTs counted once."""
    if fmt == 'NONE':
        return dict(logic=0, ff=0, apm=0, ram=0, bits=0)
    width = 32 if fmt == 'F' else 64
    precisions = (24,) if fmt == 'F' else (24, 53)
    if scheme == 'wide':
        precisions = (53,)
    logic = sum(datapath(p)[0] for p in precisions)
    ff = sum(datapath(p)[1] + sum(cascade(p)[1:]) for p in precisions)
    apm = sum(len(cascade(p)[0]) for p in precisions)
    if scheme == 'unified':
        logic -= 200 * len(precisions)
        ff -= 96 * len(precisions)
    if scheme == 'split':
        logic += datapath(24)[0] // 3
        ff += datapath(24)[1] // 3
    if scheme == 'serial_d':
        apm = 2
        ff -= sum(cascade(53)[1:]) - (106 + 96)
    # C2-I two interleaved banks, result+PC; no redundant FP-only completion RAM.
    copies = reads + 1 if queue_forward else 1
    ram = reads * width + 2 * (copies * width + 32)
    bits = reads * 32 * width + depth * (copies * width + 32)
    tag = ceil(log2(depth))
    scoreboard_ff = 32 * (1 + tag)
    scoreboard_lut = 32 * (1 + tag) + 10 * depth
    logic += 6 * (width + 32) + scoreboard_lut + 48
    ff += 18 * depth + 32 - 4 * 77 + scoreboard_ff + 10
    return dict(logic=logic, ff=ff, apm=apm, ram=ram, bits=bits)


def main():
    verify_cascade()
    base = estimate('V5-default')
    for p in (24, 53):
        terms, src, residual = cascade(p)
        print(f'p={p}, L/Q={datapath(p)}, weights={[t[0] for t in terms]}, '
              f'APM={len(terms)}, internal cycles={len(terms)+2}, '
              f'external source/residual FF={src}/{residual}')
    print('|配置/队列|增量总LUT/逻辑LUT|增量FF|增量APM|LUTRAM/逻辑bit|增量CLM|CPU LUT/FF/APM/CLM|')
    print('|---|---:|---:|---:|---:|---:|---|')
    for fmt, depth in (('NONE', 4), ('F', 8), ('F', 16), ('FD', 8), ('FD', 16)):
        row = resources(fmt, depth)
        lut = row['logic'] + row['ram']
        clm = ceil(max(lut / 4, row['ff'] / 8) / .70)
        total_lut, total_ff = base['lut'] + lut, base['ff'] + row['ff']
        total_clm = ceil(max(total_lut / 4, total_ff / 8) / .70)
        print(f'|{fmt}/{depth}|{lut}/{row["logic"]}|{row["ff"]}|{row["apm"]}|'
              f'{row["ram"]}/{row["bits"]}|{clm}|'
              f'{total_lut}/{total_ff}/{base["apm"]+row["apm"]}/{total_clm}|')
    for fmt in ('F', 'FD'):
        for reads in (2, 3):
            print(fmt, f'{reads}R head-only:',
                  resources(fmt, reads=reads, queue_forward=False))
    for scheme in ('unified', 'bypass', 'split', 'wide', 'serial_d'):
        print(scheme, 'FD/8:', resources('FD', scheme=scheme))


if __name__ == '__main__':
    main()
