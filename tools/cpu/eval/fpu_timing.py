#!/usr/bin/env python3
# fpu_timing.py — C2-F2 segment estimates; CPU v2 design §3, host clock.
# Reuse C2-I calibration without modifying its integer-core model.
"""Print candidate stages; all delays are planning estimates, not PDS results."""
from math import ceil
from v2_estimates import Q, HFF, ADD32, LOOPS


def carry(width):
    """Extend the observed carry32 cell pattern by four-bit carry groups."""
    return ADD32 + (ceil(width / 4) - 8) * .090


def segment(levels, width=0):
    return HFF + levels * Q + (carry(width) if width else 0) + .450


# Label, count, ordinary LUT levels on critical serial path, carry width, APM.
# Parallel exponent/classification work is not summed into the barrel path.
STAGES = {
    'S FMA': [('E1 classify/LZ', 1, 6, 0, False),
              ('E2 normalize inputs → APM X/Y', 1, 5, 0, False),
              ('E3-E5 cascade', 3, 0, 0, True),
              ('E6 add/LZA parallel', 1, 3, 77, False),
              ('E7 LZA/select + shift4', 1, 6, 0, False),
              ('E8 shift3/round/pack', 1, 4, 24, False)],
    'S ADD': [('A1 exponent/classify', 1, 3, 13, False),
              ('A2 align/select', 1, 6, 0, False),
              ('A3 add/LZA parallel', 1, 3, 28, False),
              ('A4 normalize', 1, 5, 0, False),
              ('A5 round/pack', 1, 2, 24, False)],
    'S MUL': [('M1 classify/LZ', 1, 6, 0, False),
              ('M2 normalize → APM X/Y', 1, 5, 0, False),
              ('M3-M5 cascade', 3, 0, 0, True),
              ('M6 underflow shift', 1, 6, 0, False),
              ('M7 round/pack', 1, 2, 24, False)],
    'D FMA': [('E1 classify/LZ', 1, 6, 0, False),
              ('E2 normalize inputs → APM X/Y', 1, 6, 0, False),
              ('E3-E15 cascade', 13, 0, 0, True),
              ('E16-E17 sliced add/LZA', 2, 2, 84, False),
              ('E18 LZA/select + shift4', 1, 6, 0, False),
              ('E19 shift4/correct', 1, 5, 0, False),
              ('E20 round/pack', 1, 2, 53, False)],
    'D ADD': [('A1 exponent/classify', 1, 3, 13, False),
              ('A2 align6', 1, 6, 0, False),
              ('A3 align2/add', 1, 2, 57, False),
              ('A4 LZA final2/shift4', 1, 6, 0, False),
              ('A5 shift2/correct', 1, 4, 0, False),
              ('A6 round/pack', 1, 2, 53, False)],
    'D MUL': [('M1 classify/LZ', 1, 6, 0, False),
              ('M2 normalize → APM X/Y', 1, 6, 0, False),
              ('M3-M15 cascade', 13, 0, 0, True),
              ('M16 underflow shift4', 1, 4, 0, False),
              ('M17 shift2/correct', 1, 3, 0, False),
              ('M18 round/pack', 1, 2, 53, False)],
    'S DIV/SQRT': [('prepare', 2, 6, 0, False),
                   ('digit select/recurrence', 14, 4, 28, False),
                   ('residual correction/LZ', 1, 3, 28, False),
                   ('normalize', 1, 5, 0, False),
                   ('round/pack', 1, 2, 24, False)],
    'D DIV/SQRT': [('prepare', 2, 6, 0, False),
                   ('digit select/root mux/recurrence', 28, 3, 57, False),
                   ('residual correction/LZ', 1, 3, 57, False),
                   ('LZ finish/shift4', 1, 6, 0, False),
                   ('shift2/correct', 1, 3, 0, False),
                   ('round', 1, 2, 53, False),
                   ('pack/flags', 1, 3, 0, False)],
    'S convert': [('classify/LZ', 1, 6, 0, False),
                  ('shift/range', 1, 6, 0, False),
                  ('round/saturate/pack', 1, 3, 32, False)],
    'D convert': [('classify/LZ', 1, 6, 0, False),
                  ('shift6', 1, 6, 0, False),
                  ('shift/range', 1, 3, 0, False),
                  ('round/saturate/pack', 1, 3, 53, False)],
    'compare/min/class': [('classify/compare', 1, 3, 32, False),
                          ('reduce/select/box', 1, 4, 0, False)],
    'sign/move': [('sign/box/move', 1, 3, 0, False)],
}


def latency(name):
    return sum(row[1] for row in STAGES[name])


def main():
    print('|路径|阶段（重复次数）|APM|carry位|普通级|扇出目标|估算 ns|')
    print('|---|---|---:|---:|---:|---|---:|')
    for name, rows in STAGES.items():
        for label, count, levels, width, apm in rows:
            parallel = {('S ADD', 'A3 add/LZA parallel'): 5,
                        ('D ADD', 'A3 align2/add'): 6,
                        ('S DIV/SQRT', 'residual correction/LZ'): 5,
                        ('D DIV/SQRT', 'residual correction/LZ'): 6}.get((name, label), 0)
            delay = LOOPS['multiply'] + .450 if apm else segment(levels, width)
            delay = max(delay, segment(parallel)) if parallel else delay
            logic_label = f'{levels}（并行{parallel}）' if parallel else str(levels)
            print(f'|{name}|{label} ×{count}|{int(apm)}|{width}|{logic_label}|'
                  f'{"级联专线/叶≤16" if apm else "根≤8/叶≤16"}|{delay:.3f}|')


if __name__ == '__main__':
    main()
