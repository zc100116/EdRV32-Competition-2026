#!/usr/bin/env python3
# File: v2_estimates.py; Spec: C2-I timing/area planning; Clock: host.
# Keep formulas and their assumed inputs executable alongside trace results.
# Areas are module budgets, not synthesis results; frequency is conditional on SoC closure.
"""python3 tools/cpu/eval/v2_estimates.py prints the modeled P/F/R table."""
import json
import math
from pathlib import Path


Q = .242 + .500  # slow LUT + target local route, ns
HFF = .261 + .406 + .200 + .324
HDRM = 1.644 + .406 + .200 + .324
ADD32 = .405 + 7 * .090 + .224
MUX = .293 + .500
# Full 32-bit RF selection is explicitly separate from ALU bypass selection.
LOOPS = {
    'alu_bypass': HFF + ADD32 + 4 * Q,
    'next_pc': HFF + ADD32 + 4 * Q,
    'load_to_ex': HDRM + 3 * Q,
    'dcache_tag_local': HDRM + 3 * Q,
    'local_control': HFF + 4 * Q,
    'decode_rf': HFF + 3 * MUX + 3 * Q,
    'multiply': 3.443 + .500 + .406 + .200 + .324,
    'if_tag_mux': HDRM + 3 * Q,
}
# (LUT, FF), excluding RAM macros. Budget sums are deliberately visible.
MODULES = {
    'regfile': (2235, 992), 'alu_x2': (792, 0), 'branch_x2': (65, 0),
    'mul': (1, 133), 'div': (242, 139), 'csr_hpm2': (500, 480),
    'gshare1024_btb64_ras4': (300, 240), 'if_id_queue': (500, 450),
    'decode_issue': (500, 150), 'forwarding': (800, 200),
    'pipeline_local_control': (300, 960), 'icache_ctrl': (1000, 550),
    'dcache_ctrl': (1500, 700), 'cache_apb': (54, 161),
}
DEFAULT_LUT = sum(v[0] for v in MODULES.values())
DEFAULT_FF = sum(v[1] for v in MODULES.values())
# Entries: delta LUT/FF from V5-default; extra critical delay (ns); DRM36K/APM.
DELTAS = {
    'V5-default': (0, 0, 0, 18, 4),
    'V5': (220, 64, 0, 18, 4),
    'V5-redirect3': (220, 96, 0, 18, 4),
    'V5-dual-lsu': (220 + 640, 64 + 224, Q, 18, 4),
    'V5-cascade': (220 + 48, 64, 0, 18, 4),
    'V5-fuse-lui': (220 + 2500, 64 + 688, 0, 18, 4),
    'V5-fuse-call': (220 + 1356, 64 + 344, 0, 18, 4),
    'V5-fuse-compare': (220 + 128, 64 + 128, Q, 18, 4),
    'V5-tournament': (1230, 250, 0, 18, 4),
    'V5-gshare1024': (120, 64, 0, 18, 4),
    'V5-btb64': (100, 0, 0, 18, 4),
    'V5-btb256': (460, 192, 0, 18, 4),
    'V5-ras8': (252, 192, 0, 18, 4),
    'V5-full': (1230 + 32 + 2500 + 1038, 250 + 128 + 688 + 388, Q, 18, 4),
    'V5-ip-full': (1230 + 32 + 1038, 250 + 128 + 388, 0, 18, 4),
    'V5-1': (-1110 - 396 - 32 - 200 - 100, -128 - 200 - 150, 0, 18, 4),
    'V5-drm-fetch': (220 - 150, 64 + 128, 0, 18, 4),
    'V5-zba': (220 + 128, 64, Q, 18, 4),
    'V5-zbb': (220 + 320, 64, Q, 18, 4),
    'V5-zba_zbb': (220 + 448, 64, Q, 18, 4),
}


def estimate(name):
    if name == 'B0':
        # Card75 ADS u_cpu; WNS-derived same-placement sys period ceiling only.
        lut, ff, period, drm, apm = 19238, 12109, 7.999 + .546, 27, 4
        frequency = 1000 / period
        stress_frequency = frequency
    else:
        dlut, dff, extra, drm, apm = DELTAS[name]
        lut, ff = DEFAULT_LUT + dlut, DEFAULT_FF + dff
        period = max(LOOPS.values()) + extra
        if name == 'V5-cascade':
            period = max(period, HFF + 2 * ADD32 + 5 * Q)
        if name in {'V5-zbb', 'V5-zba_zbb'}:
            period = max(period, HFF + 8 * Q)  # count tree5 + select1 + bypass2
        period += .450  # explicit unmodeled local placement/clock-distribution allowance
        # 5% frequency reserve for whole-SoC congestion, rounded down to 5 MHz.
        frequency = 5 * math.floor((1000 / period / 1.05) / 5)
        stress_frequency = 5 * math.floor((1000 / period / 1.182) / 5)
    clm = math.ceil(max(lut / 4, ff / 8) / .70)
    return dict(lut=lut, ff=ff, clm=clm, drm=drm, apm=apm,
                probe_period_ns=period, soc_mhz_est=frequency,
                soc_mhz_stress=stress_frequency)


def main():
    paths = [Path('build/cpu-v2') / (w + '.jsonl')
             for w in ('coremark', 'vision', 'render')]
    paths.append(Path('build/cpu-v2/isa/results.jsonl'))
    rows = [json.loads(line) for path in paths for line in path.read_text().splitlines()]
    for row in rows:
        if row['workload'] != 'coremark' or row['name'] == 'B0-no-ic-recovery':
            continue
        area = estimate(row['name'])
        perf = 10000000 / row['cycles']
        score = perf * area['soc_mhz_est']
        stress_score = perf * area['soc_mhz_stress']
        other = [next(r for r in rows if r['workload'] == w and r['name'] == row['name'])
                 for w in ('vision', 'render')]
        print(f'| {row["name"]} | {row["cycles"]:,} | {perf:.3f} | '
              f'{other[0]["ipc"]:.3f} / {other[1]["ipc"]:.3f} | '
              f'{area["soc_mhz_stress"]:.2f} / {area["soc_mhz_est"]:.2f} | '
              f'{area["lut"]:,} / {area["ff"]:,} | '
              f'{area["clm"]:,} | {area["drm"]} / {area["apm"]} | '
              f'{stress_score:.1f} / {score:.1f} | '
              f'{stress_score / (area["lut"] / 1000):.1f} / '
              f'{score / (area["lut"] / 1000):.1f} |')


if __name__ == '__main__':
    main()
