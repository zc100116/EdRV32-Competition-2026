#!/usr/bin/env python3
# File: wide_estimates.py; Spec: T-CPU-WIDE resource/timing estimates; Clock: host.
# Translate explicitly assumed FF arrays, mux trees and stage depths into budgets.
# These are structural estimates relative to card48, not synthesis measurements.
"""Print candidate estimates; formulas and limitations are in the design record."""
import json
from math import ceil, log2, log

from run_wide_ooo_eval import INORDER, OOO


def mux(k):
    return ceil((k - 1) / 3)


def rf(p, reads, writes):
    return 32 * reads * mux(p - 1) + 32 * (p - 1) * mux(writes) + p * writes


def bypass(n, sources, tag_luts=1):
    return 64 * n * mux(sources + 1) + 2 * n * sources * tag_luts


def estimates(name, options):
    ordered = name.startswith('I')
    n = options['width'] if ordered else options['issue_width']
    l = options['lsus']
    front_lut = 0 if n == 2 else 248 + 64 * (n - 2)
    front_ff = 640 * (n - 2)
    if ordered:
        a, b = options['alus'], options['branches']
        pairing = 4 * n * (n - 1) + 32 * n * mux(n)
        extra_lut = (rf(32, 2 * n, n) - rf(32, 4, 2)
                     + bypass(n, 3 * n) - bypass(2, 6)
                     + 250 * (a - 2) + 64 * (b - 1)
                     + pairing - (8 + 64)
                     + (0 if options.get('restricted') else 64 * n))
        extra_ff = 0
        depths = dict(alu=2 * ceil(log(3 * n + 1, 4)) + 1 + (n > 2),
                      decode=4 + ceil(log(3 * n + 1, 4)) + 2 * n - 3 + (b > 1))
        paths = dict(alu=1.141 + 1.259 + depths['alu'] * .742,
                     decode=1.141 + depths['decode'] * .742,
                     rf=1.141 + (ceil(log(31, 4)) + ceil(log(n, 4))) * .742,
                     load=2.524 + (4 + l - 1) * .742, mul=6.450)
    else:
        r, q = options['rob_size'], options['iq_size']
        p = 32 + r
        t, age = ceil(log2(p)), ceil(log2(r))
        s = n + l + 2
        tag_luts = ceil(t / 6)
        # Every ROB position has a map/free-bitmap snapshot: no checkpoint stalls.
        snapshots = r * (32 * t + p)
        rename_ff = 64 * t + snapshots + p
        rename_lut = (2 * n * t * mux(32) + 32 * t * mux(n + 1) + 32 * n
                      + n * (n - 1) + (32 * t + p) * mux(r)
                      + snapshots * mux(n) + 82 * mux(r))
        rob_ff = r * (162 + 2 * t)
        iq_ff = q * (72 + 3 * t + age)
        lsq_ff = r * (104 + 2 * t)
        wake_lut = 2 * q * s * tag_luts
        select_lut = n * (q - 1) * ceil(age / 3) + 2 * n * t * mux(q)
        lsq_lut = l * r * (ceil(32 / 6) + ceil(age / 6) + 2) + 32 * l * mux(r)
        commit_lut = 32 * n + n * age
        extra_lut = (rf(p, 2 * n, s) - rf(32, 4, 2)
                     + bypass(n, s, tag_luts) - bypass(2, 6)
                     + rename_lut + wake_lut + select_lut + lsq_lut + commit_lut
                     + 250 * (n - 2))
        extra_ff = (32 * (p - 32) + rename_ff + rob_ff + iq_ff + lsq_ff
                    + 3 * n * 128)
        depths = dict(wakeup=tag_luts + ceil(log(s, 4)) + ceil(log2(q))
                      + ceil(log2(n)) + 1,
                      rename=max(4 + ceil(log2(n)) + 1, t + ceil(log2(n))),
                      commit=ceil(log2(n)) + 3, restore=ceil(log(r, 4)) + 2,
                      lsq=3 + ceil(log(r, 4)))
        paths = {key: 1.141 + value * .742 for key, value in depths.items()}
        paths['lsq'] += 1.259
        paths['alu'] = 1.141 + 1.259 + (ceil(log(s + 1, 4)) + tag_luts + 1) * .742
        paths['rf'] = 1.141 + (ceil(log(p - 1, 4)) + ceil(log(s, 4))) * .742
        paths['load'] = 2.524 + (4 + l - 1) * .742
        paths['mul'] = 6.450
    return dict(lut=15585 + extra_lut + front_lut + 512 * (l - 1),
                ff=9564 + extra_ff + front_ff + 192 * (l - 1), drm=18,
                fmax=1000 / max(paths.values()), depths=depths, paths_ns=paths)


if __name__ == '__main__':
    for name, options in (INORDER | OOO).items():
        print(json.dumps(dict(name=name, **estimates(name, options))))
