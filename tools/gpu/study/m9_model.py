#!/usr/bin/env python3
"""M-9 DDR/geometry rooflines and frame/resource planning, not RTL measurements.
Inputs and equations are documented in design section 11. Standard library only.
"""
import json
import math
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
import m8_model as m8

OUT = Path(__file__).resolve().parents[3] / 'build/gpu/m9'
F = 1.634
CV = 29.75
CPOS = 86 / 12
CS = 29.71372549019608
CACHE = [512, 512, 0, 4, 128]
NON_GPU = [36282, 30818, 4, 58.5, 1241]


def resource_row(name):
    r = m8.resources(variant='dedicated' if name.startswith('fast') else 'compressed')
    total = r['total'][:]
    # M-7 width savings relative to W256; undo W64, retain W256 for all candidates.
    total = [a + b for a, b in zip(total, [1979, 2160, 0, 0, 672])]
    if name != 'baseline':
        total = [a + b for a, b in zip(total, CACHE)]
    if name.startswith('stripe'):
        strips = int(name[-1])
        # 40 bpp; retain measured 129-bank packing ratio of the 180-row target.
        target = math.ceil(129 * 2 / strips)
        total = [a - b for a, b in zip(total, [1808, 1728, 0, 9, 404])]
        total[3] += target - 5
        # Keep conservative target control cost despite deleting bin/overlap.
    soc = [a + b for a, b in zip(total, NON_GPU)]
    clm = lambda r: math.ceil(max(r[0] / 4, r[1] / 8) / .70)
    return dict(total=total, soc_drm=soc[3], gpu_clm=clm(total), soc_clm=clm(soc),
                gpu_clms=math.ceil(total[4] / 2.8), soc_clms=math.ceil(soc[4] / 2.8))


def work(name, v):
    # v=V/T. lambda is transformed/input vertex fetches per source triangle.
    idx = 6 if v == 1 else 0  # three uint16 indices, primitive list order implicit
    lam = F * v if name.endswith('ideal') else 3 * F
    cs, first = (11, 114) if name.startswith('fast') else (CS, 199)
    if name == 'baseline':
        return dict(bytes=224*v + 16*F + 288*(1+F), vertex=CV*v,
                    setup=CS, extra=11*F, first=199)
    if name.startswith('stripe'):
        s = int(name[-1])
        return dict(bytes=s*(64*v+idx), vertex=s*CV*v, setup=s*CS,
                    extra=0, first=s*199)
    if name == 'hybrid':
        # Position input once (16B), screen/depth/clip metadata write16+read16.
        # Full64B source is reread per tile; full D1 includes position again.
        return dict(bytes=32*v + 16*3*F + 64*lam + 8*F + idx,
                    vertex=CPOS*v+CV*lam, setup=CS*F, extra=11*F, first=199)
    # Compact64B vertex is FP32-preserving; plane records eliminated.
    return dict(bytes=128*v + 64*lam + 8*F + idx, vertex=CV*v,
                setup=cs*F, extra=11*F, first=first)


def rates(w, mhz, bw):
    effective = min(bw*1e9, mhz*1e6*32*.55)
    # Separate engines, ideal interstage overlap: a ceiling, not a promise.
    return min(mhz*1e6/w['vertex'], mhz*1e6/w['setup'],
               effective/w['bytes']) / 1e6


def frame(w, t, mhz, bw, scaled=False, miss=.1):
    fragments = 717910 * (t/1000 if scaled else 1)
    geometry = t*(w['vertex']+w['setup']+w['extra']) + w['first']
    pixels = fragments + 115200
    data = t*w['bytes'] + 460800 + fragments*16*miss
    effective = min(bw*1e9, mhz*1e6*32*.55)
    return dict(planning_ms=1000*(max(geometry, pixels)/(mhz*1e6)+data/effective),
                serial_ms=1000*((geometry+pixels)/(mhz*1e6)+data/effective),
                lower_ms=1000*max(geometry/(mhz*1e6), pixels/(mhz*1e6),
                                  data/effective), bytes=data)


def main():
    names = ['baseline', 'tile', 'tile-ideal', 'stripe2', 'stripe3', 'stripe4',
             'hybrid', 'fast', 'fast-ideal']
    result = dict(source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                       text=True).strip(),
                  inputs=dict(refs_per_triangle=F, vertex_cycles=CV, setup_cycles=CS,
                              position_cycles=CPOS, fragment_count=717910,
                              bandwidth_GBs=[1.0, 1.5, 1.8], frequency_MHz=[150, 200]),
                  resources={}, cases=[])
    lines = ['| 方案 W256 | LUT/FF/APM/DRM/LR（估算） | GPU/整片CLM | '
             'GPU/整片CLMS规划 | 整片DRM |', '|---|---|---:|---:|---:|']
    for name in names:
        if name.endswith('ideal'):
            continue
        r = resource_row(name)
        result['resources'][name] = r
        lines.append(f'| {name} | '+ '/'.join(map(str, r['total'])) +
                     f" | {r['gpu_clm']}/{r['soc_clm']} | "
                     f"{r['gpu_clms']}/{r['soc_clms']} | {r['soc_drm']} |")
    lines += ['', '| 方案 / V:T | 几何B/T | 上限Mtri/s @150，B=1.0/1.5/1.8 | '
              '上限@200，B=1.0/1.5/1.8 | 帧ms@150/200，1.5GB/s：1k；5k；10k |',
              '|---|---:|---|---|---|']
    for name in names:
        for v in (3, 1):
            w = work(name, v)
            rate = [[rates(w, f, b) for b in (1., 1.5, 1.8)] for f in (150, 200)]
            frames = {str(t): {str(f): {str(b): frame(w, t, f, b)
                                      for b in (1., 1.5, 1.8)} for f in (150, 200)}
                      for t in (1000, 5000, 10000)}
            scaled = {str(t): [frame(w, t, f, 1.5, scaled=True)['planning_ms']
                               for f in (150, 200)] for t in (5000, 10000)}
            result['cases'].append(dict(name=name, v=v, work=w, rates=rate,
                                        frames=frames, scaled=scaled))
            fmt = lambda xs: '/'.join(f'{x:.3f}' for x in xs)
            times = '; '.join(fmt([frames[str(t)][str(f)]['1.5']['planning_ms']
                                  for f in (150, 200)]) for t in (1000, 5000, 10000))
            lines.append(f'| {name} / {v} | {w["bytes"]:.3f} | '+
                         ' | '.join(fmt(xs) for xs in rate)+f' | {times} |')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'm9-model.json').write_text(json.dumps(result, indent=2)+'\n')
    (OUT / 'tables.md').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
