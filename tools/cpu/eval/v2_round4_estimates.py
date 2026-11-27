#!/usr/bin/env python3
# File: v2_round4_estimates.py; Spec: C2-I4 timing/resources; Clock: host.
# Reuse Q/HFF/HDRM/ADD32/MUX and the round-one frequency/packing formulas.
# RAM fragmentation is counted separately from logical storage bits.
"""python3 tools/cpu/eval/v2_round4_estimates.py > build/cpu-v2-round4/tables.md."""
import json
import math
from pathlib import Path

from run_v2_round4 import BASES, EXPERIMENTS
from v2_estimates import Q, HFF, HDRM, ADD32, MUX
from v2_round3_estimates import estimate as third
from v2_round2_estimates import estimate as second
from v2_round4_structures import HISTORIES

# These retain the exact asynchronous RF cycle model; only placement and
# queued-owner tracking differ. Explicit aliases never substitute missing data.
HEAD_ALIASES = {'rf-head': 'rf-async'}
for number in (3, 4, 5):
    HEAD_ALIASES[f'combo{number}-head'] = f'combo{number}'
    HEAD_ALIASES[f'combo{number}-zba-head'] = f'combo{number}-zba'


def estimate(base, name):
    a = third('default2-early-div' if base == 'default' else 'full2-no-late',
              'base' if base == 'default' else 'combo-control')
    if base == 'small':
        old = second('small2-early-div')
        a.update(lut=old['lut'], ff=old['ff'], period=old['probe_period_ns'])
    source = HEAD_ALIASES.get(name, name)
    c = dict(EXPERIMENTS[source])
    if name in HEAD_ALIASES:
        c['rf'] = 'head'
    lut, ff, drm = a['lut'], a['ff'], a['drm']
    critical = a['period'] - .450
    tage = c.get('tage')
    bank = c.get('unaligned_fetch', False)
    rf = c.get('rf', name.removeprefix('rf-') if name.startswith('rf-') else None)
    predictor_bits = 21004 if base == 'full' or name == 'tournament4096' else 8204
    metadata_bits = 0
    if name == 'tournament4096' and base == 'default':
        lut += 1010
        ff += 186
    if tage:
        count, entries = tage
        if base == 'full':
            lut -= 1010  # Replace round-one tournament increment, retain RAS8.
            ff -= 186
        # Per table: folded index/tag32 + compare6 + counter/usefulness16
        # + update selection16; shared selection64 + update forwarding96.
        lut += count * (32 + 6 + 16 + 16) + 64 + 96
        # Saved-query sidecar: 16 entries, two write banks of eight. Each
        # table keeps index+tag, plus provider/prediction/alternate (five bits).
        key_width = count * (entries.bit_length() - 1 + 10) + 5
        metadata_bits = 16 * key_width
        lut += 2 * key_width
        ff += max(HISTORIES[count]) + count * 32 + 64
        drm += (count + 1) * .5  # Separate base/tag RAM18K allocations.
        predictor_bits = 8192 + 12 + 8192 + count * entries * 16 + max(HISTORIES[count])
        critical = max(critical, HDRM + 4 * Q, HFF + 3 * Q)
    if bank:
        # Two 32-bit data banks, two parity-banked BTB lookups, registered
        # address+4 and lane exchange; same data capacity and one target/group.
        lut += 64 + 32 + 64 + 64
        ff += 64 + 32
        if tage:
            count, _ = tage
            lut += count * (32 + 6) + 64
            ff += count * 16
            drm += (count + 1) * .5  # Two parity banks per predictor table.
        elif base == 'full' or name == 'tournament4096':
            lut += 32 + 80  # Replicate local counters for two arbitrary reads.
            ff += 64
        critical = max(critical, HDRM + 4 * Q, HFF + ADD32 + 3 * Q)
    if name == 'fetch128':
        lut += 256 if base == 'full' else 336
        ff += 128 if base == 'full' else 448
        # Round-three explicit four-word align/select critical segment.
        critical = max(critical, HDRM + 4 * Q, HFF + 3 * MUX + 4 * Q)
    if c.get('read_bytes'):
        width = c['read_bytes']
        # Second EX AGU128 + registered compare32 + qualification32 + replay64,
        # two return extractors: 32 x log2(read_bytes) selection LUT budget.
        lut += 128 + 32 + 32 + 64 + 64 * int(math.log2(width))
        ff += 2 * 32 + 2 * 32 + 32
        critical = max(critical, HFF + 2 * MUX + ADD32, HFF + 3 * Q,
                       HDRM + int(math.log2(width / 4)) * MUX + Q)
        if c.get('merge_early'):
            # Younger EX base bypass + AGU + same-block comparison must
            # qualify the older ID-addressed E read at this same edge.
            critical = max(critical, HFF + 2 * MUX + ADD32 + 3 * Q)
    if name == 'zba' or c.get('zba'):
        lut += 128  # Fixed shifted wiring feeds the existing ALU input selection.
        critical = max(critical, HFF + ADD32 + 4 * Q)
    if rf and rf != 'ff':
        lut -= 1125 if base == 'small' else 2235
        ff -= 992
        # 4 reads x 2 write-owner banks; 31-bit FF LVT, youngest write wins.
        # Bank selects128 + WB bypass128 + decode64 + LVT ctrl32,
        # plus four 32:1 single-bit owner lookups at eleven LUT each.
        lut += 128 + 128 + 64 + 32 + 44
        ff += 31 + 64 + 32
        if rf in ('async', 'head'):
            lut += 8 * 32  # Eight 32x32 async LUTRAM copies (not arithmetic tricks).
            # Assumed async RAM read1.2 + route0.5; LVT/bank/WB and ID AGU.
            # LVT is a 31-bit FF array with four 32:1 owner reads. Its
            # three mux levels are parallel with RAM, then owner/WB/AGU.
            critical = max(critical, HFF + max(1.700, 3 * MUX) + 2 * MUX + ADD32)
            if rf == 'head':
                entries = (8 if base == 'full' else 4) + 2
                # Four source/WB comparisons per queued instruction, each
                # 5-bit compare3; two owner enables; local WB distribution32
                # and four head-owner selects. The 44 LVT lookup LUT move
                # from D to F2 and are already included in the common budget.
                lut += 12 * entries + 2 * entries + 32 + 4
                # Retain both pre-alignment bank owner candidates per source,
                # plus bank select: five bits/instruction; WB copies14.
                ff += 5 * entries + 14
                critical = max(a['period'] - .450,
                               HFF + 1.700 + 2 * MUX + ADD32,
                               HDRM + 3 * MUX + MUX)
        else:
            drm += 4  # Eight dedicated RAM18K macros, severe shallow-depth waste.
            ff += 128 + 80  # Four read outputs + added decode/operand stage.
            critical = max(critical, HDRM + 2 * MUX + ADD32, HFF + 4 * Q)
        if base == 'small' and rf == 'async':
            # Two reads, one write: two copies; no LVT or owner bank mux.
            lut += (2 * 32 + 64 + 32) - (396 + 256)
            ff += 64 - 127
            # One writer needs neither LVT lookup nor owner selection.
            critical = a['period'] - .450
            critical = max(critical, HFF + 1.700 + MUX + ADD32)
    period = critical + .450
    return dict(lut=lut, ff=ff, drm=drm, apm=a['apm'], predictor_bits=predictor_bits,
                metadata_bits=metadata_bits,
                clm=math.ceil(max(lut / 4, ff / 8) / .70), period=period,
                plan=5 * math.floor(1000 / period / 1.05 / 5),
                stress=5 * math.floor(1000 / period / 1.182 / 5))


def load(root):
    rows = {(r['workload'], r['base'], r['name']): r
            for w in ('coremark', 'vision', 'render')
            for line in (root / (w + '.jsonl')).read_text().splitlines()
            if (r := json.loads(line))}
    for w in ('coremark', 'vision', 'render'):
        for base in ('default', 'full'):
            for name, source in HEAD_ALIASES.items():
                rows[w, base, name] = dict(rows[w, base, source], name=name)
    return rows


def tables(root):
    by = load(root)
    for base in ('default', 'full'):
        print('\n### ' + base + '：逐项与组合（全部为模型/资源/时序估算）\n')
        print('| 方案 | CM/视觉/LVGL周期 | ΔCPI CM/视觉/LVGL | CM/MHz | '
              'LUT/FF/CLM | DRM/APM | ns；F规划/压力 | P×F规划/压力 | P×F/kLUT规划/压力 |')
        print('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
        for name in (*EXPERIMENTS, *HEAD_ALIASES):
            rows = [by[w, base, name] for w in ('coremark', 'vision', 'render')]
            refs = [by[w, base, 'base'] for w in ('coremark', 'vision', 'render')]
            a = estimate(base, name)
            p = 1e7 / rows[0]['cycles']
            deltas = [r['cycles'] / r['instructions'] - b['cycles'] / b['instructions']
                      for r, b in zip(rows, refs)]
            print('| ' + name + ' | ' + '/'.join(f'{r["cycles"]:,}' for r in rows) +
                  ' | ' + '/'.join(f'{d:+.6f}' for d in deltas) + f' | {p:.4f} | '
                  f'{a["lut"]}/{a["ff"]}/{a["clm"]} | {a["drm"]}/{a["apm"]} | '
                  f'{a["period"]:.3f}；{a["plan"]}/{a["stress"]} | ' + '/'.join(
                      f'{p * a[k]:.2f}' for k in ('plan', 'stress')) + ' | ' + '/'.join(
                      f'{p * a[k] / (a["lut"] / 1000):.2f}' for k in ('plan', 'stress')) + ' |')
        print('\n| 方案 | 状态/新增查询侧表位（含F1，不含BTB/RAS） | CM/视觉/LVGL控制误预测（方向） | '
              'pair_one CPI CM/视觉/LVGL | F2纠正 CM/视觉/LVGL |')
        print('|---|---:|---:|---:|---:|')
        for name in ('base', 'tournament4096', 'tage3-128', 'tage3-256', 'tage3-512',
                     'tage4-256', 'tage4-512', 'tage5-256', 'tage5-512', 'tage5-1024',
                     'bank-fetch', 'fetch128', 'combo3', 'combo4', 'combo5'):
            rows = [by[w, base, name] for w in ('coremark', 'vision', 'render')]
            a = estimate(base, name)
            misses = '/'.join(f'{r["control_misses"]} ({r["direction_misses"]})' for r in rows)
            print(f'| {name} | {a["predictor_bits"]}/{a["metadata_bits"]} | ' +
                  misses + ' | ' +
                  '/'.join(f'{r["slots_pair_one"] / (2 * r["instructions"]):.6f}' for r in rows) +
                  ' | ' + '/'.join(str(r['f2_corrections']) for r in rows) + ' |')
        print('\n| 读宽/负载 | EX候选 | 合并/补读 | 同64/128/256位覆盖（占候选） |')
        print('|---|---:|---:|---:|')
        for name in ('load64', 'load128', 'load256',
                     'load64-early', 'load128-early', 'load256-early'):
            for w in ('coremark', 'vision', 'render'):
                m = by[w, base, name]['merge']
                coverage = [f'{m["coverage"][str(k)]} '
                            f'({100 * m["coverage"][str(k)] / m["candidates"]:.2f}%)'
                            for k in (8, 16, 32)]
                print(f'| {name}/{w} | {m["candidates"]} | {m["merged"]}/{m["replays"]} | ' +
                      '/'.join(coverage) + ' |')


if __name__ == '__main__':
    tables(Path('build/cpu-v2-round4'))
