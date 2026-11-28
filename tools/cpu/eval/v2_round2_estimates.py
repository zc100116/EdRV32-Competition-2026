#!/usr/bin/env python3
# File: v2_round2_estimates.py; Spec: C2-I2 P/F/R budgets; Clock: host.
# Reuse first-round delay constants and frequency/CLM formulas explicitly.
# All new budgets are estimates of proposed circuits, not synthesis measurements.
"""python3 tools/cpu/eval/v2_round2_estimates.py."""
import json
import math
from pathlib import Path

from v2_estimates import ADD32, HFF, HDRM, LOOPS, MUX, Q, estimate as first

# LUT/FF additions: ID AGU+qualifier+address registers, late ALU/branch+bypass,
# radix4 subtract/select, leading-zero trees+barrel alignment.
ID = (128 + 96 + 64, 32 + 32 + 32)
LATE = (2 * (32 + 32 + 32 + 64 + 32) + 320, 192 + 32)
BRANCH = (65, 128)
RADIX4 = (192, 32)
EARLY_DIV = (2 * 32 + 3 * 32, 32)


def estimate(name):
    if name in ('B0', 'V5', 'V5-default', 'V5-ip-full'):
        return first(name)
    base = first('V5')
    lut, ff, drm = base['lut'], base['ff'], 18
    loops = dict(LOOPS)
    if name.startswith('B0'):
        base = first('B0')
        lut, ff, drm = base['lut'], base['ff'], 27
    if name in ('B0-fix', 'B0-fix-predecode', 'B0-fix-best',
                'B0-fix-parallel', 'B0-fix-parallel-div'):
        # Card75 I$/D$/APB=6814 LUT/4570 FF, replace control only.
        # Keep 9 early-read DRM and budget extra 320 LUT/192 FF for their routing.
        lut = 19238 - 6814 + 2554 + 320 + 96
        ff = 12109 - 4570 + 1411 + 192 + 320
        loops['early_qualification'] = HFF + 6 * Q
        loops['retained_bypass'] = HFF + ADD32 + 5 * Q
        if name in ('B0-fix-parallel', 'B0-fix-parallel-div'):
            lut += 128
            loops['parallel_predecode'] = HDRM + 4 * Q
    if name in ('V5-id-address', 'default2', 'full2', 'full2-no-late', 'small2',
                'default2-early-div', 'small2-early-div'):
        lut += ID[0]
        ff += ID[1]
        loops['id_agu'] = HFF + 3 * MUX + Q + ADD32
        loops['drm_to_operand'] = HDRM + 3 * Q
    if name in ('V5-late-alu', 'V5-late-branch', 'full2'):
        lut += LATE[0]
        ff += LATE[1]
        loops['late_alu'] = HDRM + 2 * Q + ADD32
        if name != 'V5-late-alu':
            lut += BRANCH[0]
            ff += BRANCH[1]
            loops['late_branch'] = HDRM + 3 * Q + ADD32
    if name == 'V5-pht-drm':
        # Remove 128 LUTRAM PHT bits, retain BTB, add 32 request/update LUT.
        lut += -128 + 32
        ff += 32
        drm += .5
        loops['pht_output'] = HDRM + 2 * Q
    if (name in ('B0-fix-best', 'B0-fix-parallel-div', 'default2', 'full2',
                 'full2-no-late', 'small2') or
            name.endswith(('radix4', 'radix4-early'))):
        lut += RADIX4[0]
        ff += RADIX4[1]
        loops['radix4_step'] = HFF + ADD32 + 3 * Q
    if (name in ('B0-fix-best', 'B0-fix-parallel-div', 'default2', 'full2',
                 'full2-no-late', 'small2') or
            name.endswith(('early-div', 'radix4-early'))):
        lut += EARLY_DIV[0]
        ff += EARLY_DIV[1]
        loops['div_setup'] = HFF + ADD32 + 4 * Q
        loops['div_align'] = HFF + 3 * MUX
    if name in ('full2', 'full2-no-late'):
        full = first('V5-ip-full')
        lut += full['lut'] - first('V5')['lut']
        ff += full['ff'] - first('V5')['ff']
    if name in ('small2', 'small2-early-div'):
        small = first('V5-1')
        lut += small['lut'] - first('V5')['lut'] + 100  # PHT4096, BTB64
        ff += small['ff'] - first('V5')['ff']
        lut -= 128  # HPM0 versus HPM2; cycle/instret remain
        ff -= 128
    if name.startswith('B0-') and name not in ('B0-fix', 'B0-fix-predecode', 'B0-fix-best',
                'B0-fix-parallel', 'B0-fix-parallel-div'):
        # Faster divider alone cannot repair the existing B0 critical path.
        period = max(base['probe_period_ns'], max(loops.values()) + .450)
        frequency = stress = 1000 / period
    else:
        period = max(loops.values()) + .450
        frequency = 5 * math.floor(1000 / period / 1.05 / 5)
        stress = 5 * math.floor(1000 / period / 1.182 / 5)
    return dict(lut=lut, ff=ff, clm=math.ceil(max(lut / 4, ff / 8) / .70),
                drm=drm, apm=4, probe_period_ns=period,
                soc_mhz_est=frequency, soc_mhz_stress=stress)


def tables(root):
    rows = [json.loads(line) for workload in ('coremark', 'vision', 'render')
            for line in (root / (workload + '.jsonl')).read_text().splitlines()]
    by = {(r['workload'], r['name']): r for r in rows}
    names = [r['name'] for r in rows if r['workload'] == 'coremark']
    print('| 候选 | CM / 视觉 / LVGL 周期 | CM/MHz | F压力/规划 MHz | '
          'LUT / FF | CLM | DRM / APM | CM/kLUT 压力/规划 |')
    print('|---|---|---:|---:|---:|---:|---:|---:|')
    for name in names:
        area = estimate(name)
        cycles = [by[w, name]['cycles'] for w in ('coremark', 'vision', 'render')]
        print(f'| {name} | {" / ".join(f"{c:,}" for c in cycles)} | '
              f'{1e7 / cycles[0]:.3f} | '
              f'{area["soc_mhz_stress"]:.2f}/{area["soc_mhz_est"]:.2f} | '
              f'{area["lut"]:,} / {area["ff"]:,} | {area["clm"]:,} | '
              f'{area["drm"]} / 4 | ' + ' / '.join(
                  f'{1e7 / cycles[0] * area[k] / (area["lut"] / 1000):.1f}'
                  for k in ('soc_mhz_stress', 'soc_mhz_est')) + ' |')
    print('\n| 候选 / 负载 | CPI | load-use | 误预测 | 同组RAW | 配对 | 长结果/CSR | 前端含I$ | 有效+边界 |')
    print('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
    for row in rows:
        c = row['cpi']
        print(f'| {row["name"]} / {row["workload"]} | '
              f'{row["cycles"] / row["instructions"]:.5f} | ' +
              ' | '.join(f'{c[k]:.5f}' for k in ('load_use', 'mispredict',
                 'intra_pair_raw', 'pairing', 'multiply_divide_csr',
                 'frontend_including_icache')) +
              f' | {c["effective"] + c["boundary"] + c["training"]:.5f} |')
    print('\n| 配置 | CM 每MHz / 压力F / 规划F | 视觉 每MHz / 压力F / 规划F | LVGL 每MHz / 压力F / 规划F |')
    print('|---|---:|---:|---:|')
    for name in ('B0-fix-parallel-div', 'B0-fix-best', 'default2', 'default2-early-div',
                 'full2', 'full2-no-late', 'small2', 'small2-early-div'):
        area = estimate(name)
        cells = []
        for w in ('coremark', 'vision', 'render'):
            ratio = by[w, 'B0']['cycles'] / by[w, name]['cycles']
            f0 = first('B0')['soc_mhz_est']
            cells.append(' / '.join(f'{100 * (v - 1):+.2f}%' for v in
                         (ratio, ratio * area['soc_mhz_stress'] / f0,
                          ratio * area['soc_mhz_est'] / f0)))
        print('| ' + name + ' | ' + ' | '.join(cells) + ' |')


def coverage_tables(root):
    by = {(r['workload'], r['name']): r for workload in ('coremark', 'vision', 'render')
          for line in (root / (workload + '.jsonl')).read_text().splitlines()
          if (r := json.loads(line))}
    print('\n| 负载 | B0提前/总load | ID提前/总load | late ALU数量/占N | '
          '含branch时late ALU/branch/合计占N | load-use空槽削减 ALU/含branch |')
    print('|---|---:|---:|---:|---:|---:|')
    for w in ('coremark', 'vision', 'render'):
        b, a = by[w, 'B0'], by[w, 'V5-id-address']
        l, lb, v = by[w, 'V5-late-alu'], by[w, 'V5-late-branch'], by[w, 'V5']
        print(f'| {w} | {b["early_loads"]:,}/{b["loads"]:,} '
              f'({100 * b["early_loads"] / b["loads"]:.2f}%) | '
              f'{a["early_loads"]:,}/{a["loads"]:,} '
              f'({100 * a["early_loads"] / a["loads"]:.2f}%) | '
              f'{l["late_alu"]:,}/{100 * l["late_share"]:.2f}% | '
              f'{lb["late_alu"]:,}/{lb["late_branch"]:,}/{100 * lb["late_share"]:.2f}% | '
              f'{100 * (1 - l["slots_load_use"] / v["slots_load_use"]):.2f}% / '
              f'{100 * (1 - lb["slots_load_use"] / v["slots_load_use"]):.2f}% |')
    print('\n| 架构/负载 | HPM10 原/基4/提前结束/组合 | 周期削减 基4/提前结束/组合 |')
    print('|---|---:|---:|')
    for w in ('coremark', 'vision', 'render'):
        for architecture in ('B0', 'V5'):
            cases = [by[w, architecture + suffix]
                     for suffix in ('', '-radix4', '-early-div', '-radix4-early')]
            print(f'| {architecture}/{w} | ' +
                  ' / '.join(f'{r["hpm10"]:,}' for r in cases) + ' | ' +
                  ' / '.join(f'{cases[0]["cycles"] - r["cycles"]:,}'
                             for r in cases[1:]) + ' |')


def software_tables(root):
    print('\n| 调度 / 负载 | 指令 | 周期 | 相对裸V5周期 | load-use空槽 | 空槽变化 | CPI |')
    print('|---|---:|---:|---:|---:|---:|---:|')
    stack_rows = []
    for workload in ('coremark', 'vision', 'render'):
        baseline = next(r for line in (root / (workload + '.jsonl')).read_text().splitlines()
                        if (r := json.loads(line))['name'] == 'V5')
        for tune in ('rocket', 'sifive7', 'load2'):
            row = json.loads((root / 'schedule' / tune / workload / 'result.json').read_text())
            stack_rows.append(row)
            print(f'| {tune} / {workload} | {row["instructions"]:,} | '
                  f'{row["cycles"]:,} | {100 * (row["cycles"] / baseline["cycles"] - 1):+.2f}% | '
                  f'{row["slots_load_use"]:,} | '
                  f'{row["slots_load_use"] - baseline["slots_load_use"]:+,} | '
                  f'{row["cycles"] / row["instructions"]:.5f} |')
    print('\n| 调度 / 负载 | load-use CPI | 误预测 | 同组RAW | 配对 | 长结果/CSR | 前端含I$ | 有效+边界 |')
    print('|---|---:|---:|---:|---:|---:|---:|---:|')
    for row in stack_rows:
        c = row['cpi']
        print(f'| {row["name"]} / {row["workload"]} | ' +
              ' | '.join(f'{c[k]:.5f}' for k in ('load_use', 'mispredict',
                 'intra_pair_raw', 'pairing', 'multiply_divide_csr',
                 'frontend_including_icache')) +
              f' | {c["effective"] + c["boundary"] + c["training"]:.5f} |')


if __name__ == '__main__':
    tables(Path('build/cpu-v2-round2'))
    coverage_tables(Path('build/cpu-v2-round2'))
    software_tables(Path('build/cpu-v2-round2'))
