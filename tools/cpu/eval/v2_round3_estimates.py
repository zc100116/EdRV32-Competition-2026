#!/usr/bin/env python3
# File: v2_round3_estimates.py; Spec: C2-I3 P/F/R comparison; Clock: host.
# Report explicit circuit budgets using round-one delay and packing formulas.
# Frequency and resources are estimates; ceiling rows never enter recommendations.
"""python3 tools/cpu/eval/v2_round3_estimates.py > build/cpu-v2-round3/tables.md."""
import json
import math
from pathlib import Path

from v2_estimates import HFF, HDRM, ADD32, Q, MUX
from v2_round2_estimates import estimate as second, LATE, BRANCH
from run_v2_round3 import EXPERIMENTS


def estimate(base, name):
    area = dict(second(base))
    lut, ff, apm = area['lut'], area['ff'], area['apm']
    config = EXPERIMENTS[name]
    # Keep the shared ID/decode/ALU critical loops of round two.
    critical = area['probe_period_ns'] - .450
    if config.get('late_execute'):
        lut += LATE[0] + 128  # two simple ALUs + forwarding + same-group age selectors
        ff += LATE[1] + 64  # register both older EX results before younger MEM execution
        critical = max(critical, HFF + 2 * MUX + ADD32 + Q)
        if config['late_execute'] == 'alu_branch':
            lut += BRANCH[0]
            ff += BRANCH[1]
            critical = max(critical, HFF + 2 * MUX + ADD32 + 2 * Q)
    if config.get('slot1_mul'):
        lut += 96  # operand age select64 + dispatch32, one pipelined multiplier
        ff += 32
        critical = max(critical, HFF + 4 * Q)
    if name == 'dual-mul':
        lut += 1 + 128 + 128  # multiplier + routing + four additional completion entries
        ff += 133 + 64 + 308
        apm += 4
    if config.get('slot1_lsu'):
        lut += 96  # one LSU chooses either instruction by age
        ff += 32
        critical = max(critical, HFF + 4 * Q)
    if config.get('slot1_control'):
        lut += 64  # JALR operand/target age selection at either slot
        ff += 32
        critical = max(critical, HFF + ADD32 + 4 * Q)
    if name == 'branch-two':
        lut += 192  # single-port training queue/age arbitration and local backpressure
        ff += 128
        critical = max(critical, HFF + ADD32 + 5 * Q)
    if config.get('dual_lsu'):
        lut += 640 + 288  # round-one dual hit port + second ID AGU/qualifier
        ff += 224 + 96
        critical = max(critical, area['probe_period_ns'] - .450 + Q)
    if config.get('fetch_bytes') == 16:
        lut += 256 + 4 * 20  # wider predecode/align256 + four 80-bit queue entries / 4
        ff += 128 + 4 * 80
        critical = max(critical, HDRM + 4 * Q, HFF + 3 * MUX + 4 * Q)
    if config.get('queue_depth'):
        entries = config['queue_depth'] - (8 if config.get('fetch_bytes') == 16 else 4)
        lut += entries * 20 + 32
        ff += entries * 80 + 16
        # Two fixed head registers and banked tail avoid widening RF/issue selection.
        critical = max(critical, HFF + 3 * MUX + 3 * Q)
    period = critical + .450
    return dict(lut=lut, ff=ff, apm=apm, drm=area['drm'],
                clm=math.ceil(max(lut / 4, ff / 8) / .70), period=period,
                plan=5 * math.floor(1000 / period / 1.05 / 5),
                stress=5 * math.floor(1000 / period / 1.182 / 5))


def load(root):
    return {(r['workload'], r['name']): r for w in ('coremark', 'vision', 'render')
            for line in (root / (w + '.jsonl')).read_text().splitlines()
            if (r := json.loads(line))}


def tables(root):
    by = load(root)
    for base in ('default2-early-div', 'full2-no-late'):
        print('\n### 上限和结构重放：`' + base + '`（模型估算）\n')
        print('| 单项理想化 | CM周期 | CM/MHz（增量） | 视觉IPC（增量） | LVGL IPC（增量） |')
        print('|---|---:|---:|---:|---:|')
        baseline = [by[w, base + '/base'] for w in ('coremark', 'vision', 'render')]
        for label in ('base', 'ideal-prediction', 'ideal-load', 'ideal-raw',
                      'ideal-pair', 'ideal-second', 'ideal-mul', 'ideal-all'):
            rows = [by[w, base + '/' + label] for w in ('coremark', 'vision', 'render')]
            p = 1e7 / rows[0]['cycles']
            print(f'| {label} | {rows[0]["cycles"]:,} | {p:.4f} '
                  f'({p - 1e7 / baseline[0]["cycles"]:+.4f}) | ' + ' | '.join(
                      f'{r["ipc"]:.4f} ({r["ipc"] - b["ipc"]:+.4f})'
                      for r, b in zip(rows[1:], baseline[1:])) + ' |')
        print('\n| 结构实验 | CM / 视觉 / LVGL 周期 | CM/MHz | 视觉/LVGL IPC | '
              'LUT/FF | CLM | DRM/APM | F压力/规划 | P×F压力/规划 | P×F/kLUT压力/规划 |')
        print('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
        for name in EXPERIMENTS:
            rows = [by[w, base + '/' + name] for w in ('coremark', 'vision', 'render')]
            a = estimate(base, name)
            p = 1e7 / rows[0]['cycles']
            print(f'| {name} | ' + '/'.join(f'{r["cycles"]:,}' for r in rows) +
                  f' | {p:.4f} | {rows[1]["ipc"]:.4f}/{rows[2]["ipc"]:.4f} | '
                  f'{a["lut"]}/{a["ff"]} | {a["clm"]} | {a["drm"]}/{a["apm"]} | '
                  f'{a["stress"]}/{a["plan"]} | ' + '/'.join(
                      f'{p * a[k]:.1f}' for k in ('stress', 'plan')) + ' | ' + '/'.join(
                      f'{p * a[k] / (a["lut"] / 1000):.2f}' for k in ('stress', 'plan')) + ' |')
    print('\n### 第二条不足：取指宽度、目标对齐和队列\n')
    print('| 负载 | 实际taken控制 | 64位末字目标（占taken） | 128位末字目标（占taken） |')
    print('|---|---:|---:|---:|')
    for w in ('coremark', 'vision', 'render'):
        a = by[w, 'default2-early-div/base']['alignment']
        total = a['taken_controls']
        print(f'| {w} | {total:,} | {a["target_tail64"]:,} '
              f'({100 * a["target_tail64"] / total:.2f}%) | {a["target_tail128"]:,} '
              f'({100 * a["target_tail128"] / total:.2f}%) |')
    print('\n| 基点/取指方案/负载 | pair_one CPI | 目标后/其余 CPI | 前端 CPI | 误预测 CPI |')
    print('|---|---:|---:|---:|---:|')
    for base in ('default2-early-div', 'full2-no-late'):
        for name in ('base', 'fetch128', 'queue8', 'queue16', 'fetch128-q16'):
            for w in ('coremark', 'vision', 'render'):
                r = by[w, base + '/' + name]
                n = 2 * r['instructions']
                one = r['one_breakdown']
                miss = sum(r['slots_' + k] for k in (
                    'wrong_path', 'redirect_d', 'redirect_e', 'redirect_m'))
                print(f'| {base}/{name}/{w} | {r["slots_pair_one"] / n:.6f} | '
                      f'{one.get("taken_target", 0) / n:.6f}/'
                      f'{one.get("sequential", 0) / n:.6f} | '
                      f'{r["slots_frontend"] / n:.6f} | {miss / n:.6f} |')
    print('\n### 配对类型和结构分解\n')
    print('| 负载 | pair_type CPI | pair_structural CPI | pair_one CPI | '
          'pair_one: taken后/顺序 CPI |')
    print('|---|---:|---:|---:|---:|')
    for w in ('coremark', 'vision', 'render'):
        r = by[w, 'default2-early-div/base']
        n = 2 * r['instructions']
        print(f'| {w} | ' + ' | '.join(f'{r["slots_" + c] / n:.6f}'
              for c in ('pair_type', 'pair_structural', 'pair_one')) + ' | ' +
              '/'.join(f'{r["one_breakdown"].get(c, 0) / n:.6f}'
                       for c in ('taken_target', 'sequential')) + ' |')
    for w in ('coremark', 'vision', 'render'):
        r = by[w, 'default2-early-div/base']
        n = 2 * r['instructions']
        print('\n| ' + w + ' 配对组合（老+年轻，互斥空槽） | 空槽 | CPI |')
        print('|---|---:|---:|')
        items = sorted(r['pair_breakdown'].items(), key=lambda kv: -kv[1])
        for key, value in items[:12]:
            print(f'| {key} | {value:,} | {value / n:.6f} |')
        for cause in ('pair_type', 'pair_structural'):
            value = sum(v for key, v in items[12:] if key.startswith(cause + ':'))
            print(f'| 其余 {cause} | {value:,} | {value / n:.6f} |')
    print('\n### 双 ALU 覆盖和 CPI 迁移\n')
    print('| 基点/结构/负载 | late ALU/分支 | late占退休% | 同组RAW CPI | load-use CPI | '
          '长结果 CPI | MEM恢复/总误预测 CPI |')
    print('|---|---:|---:|---:|---:|---:|---:|')
    for base in ('default2-early-div', 'full2-no-late'):
        for name in ('base', 'late-alu', 'late-branch', 'combo-alu', 'combo-branch',
                     'combo-branch-queue', 'combo-control'):
            for w in ('coremark', 'vision', 'render'):
                r = by[w, base + '/' + name]
                n = 2 * r['instructions']
                miss = sum(r['slots_' + k] for k in (
                    'wrong_path', 'redirect_d', 'redirect_e', 'redirect_m'))
                print(f'| {base}/{name}/{w} | {r["late_alu"]:,}/{r["late_branch"]:,} | '
                      f'{100 * r["late_share"]:.2f} | {r["slots_pair_raw"] / n:.6f} | '
                      f'{r["slots_load_use"] / n:.6f} | {r["slots_other_result"] / n:.6f} | '
                      f'{r["slots_redirect_m"] / n:.6f}/{miss / n:.6f} |')


if __name__ == '__main__':
    tables(Path('build/cpu-v2-round3'))
