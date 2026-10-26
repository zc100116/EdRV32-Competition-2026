#!/usr/bin/env python3
# File: run_inorder_max.py; Spec: cpu-spec 2.3, 4.1-4.4 and C-E9 task; Clock: host.
# Measure B0 and each independent remaining in-order extension on four CoreMark traces.
# Select positive geometric-mean extensions for B8; keep at most two model processes.
"""Source edrv32/env.sh, prepare C-E4 inputs, then run from the repository root."""
from concurrent.futures import FIRST_COMPLETED, ProcessPoolExecutor, wait
import csv
import math
from itertools import islice
from pathlib import Path

from pipe_model import INORDER_VARIANTS, simulate
from run_pipeline_analysis import CONFIGS, load

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/cpu_inorder_max'
BASELINES = ('V0', 'V2s', 'V2s+V5', 'L2b+V5')


def evaluate(job):
    rvc, option, variant, changes, components = job
    if changes:
        INORDER_VARIANTS[variant] = changes
    program, symbols, trace = load((rvc, option))
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'], variant)
    print(f'RVC={rvc} {option} {variant}: {result["cycles"]} cycles, '
          f'{result["ipc"]:.6f} IPC, pending peak {result["training_peak"]}', flush=True)
    return dict(rvc=rvc, option=option, variant=variant, components=components, **result)


def write(rows):
    with (OUT / 'results.csv').open('w') as log:
        writer = csv.DictWriter(log, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def run_jobs(pool, jobs, rows):
    work = iter(jobs)
    pending = {pool.submit(evaluate, job) for job in islice(work, 2)}
    while pending:
        done, pending = wait(pending, return_when=FIRST_COMPLETED)
        for future in done:
            rows.append(future.result())
            write(rows)
            if job := next(work, None):
                pending.add(pool.submit(evaluate, job))


def select(rows):
    b0 = {(r['rvc'], r['option']): r['cycles'] for r in rows if r['variant'] == 'B0'}
    scores = {variant: math.exp(sum(math.log(b0[r['rvc'], r['option']] / r['cycles'])
                                   for r in rows if r['variant'] == variant) / len(CONFIGS))
              for variant in INORDER_VARIANTS if variant not in {'B0', 'B5'}}
    groups = (('B1',), ('B2-load', 'B2'), ('B3',), ('B4',), ('B6-ras', 'B6'), ('B7',))
    selected = [max(group, key=scores.__getitem__) for group in groups]
    selected = [variant for variant in selected if scores[variant] > 1]
    changes = {}
    for variant in selected:
        changes.update(INORDER_VARIANTS[variant])
    return changes, '+'.join(selected)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    variants = BASELINES + tuple(INORDER_VARIANTS)
    with ProcessPoolExecutor(max_workers=2) as pool:
        run_jobs(pool, ((rvc, option, variant, {}, '') for variant in variants
                        for rvc, option in CONFIGS), rows)
        changes, components = select(rows)
        print(f'B8 components: {components}; settings: {changes}', flush=True)
        run_jobs(pool, ((rvc, option, 'B8', changes, components)
                        for rvc, option in CONFIGS), rows)
    bounded = [(r['rvc'], r['option'], r['variant'] + '-1buf',
                (changes if r['variant'] == 'B8' else INORDER_VARIANTS[r['variant']]) |
                {'training_capacity': 1}, r['components'])
               for r in rows if r['variant'] in {'B0', 'B4', 'B8'} and
               r['training_peak'] > 1]
    if bounded:
        with ProcessPoolExecutor(max_workers=2) as pool:
            run_jobs(pool, bounded, rows)
    references = {(r['rvc'], r['option'], r['variant']): r for r in rows}
    for row in rows:
        key = row['rvc'], row['option']
        v0, b0 = (references[*key, variant] for variant in ('V0', 'B0'))
        row['speed_v0'] = v0['cycles'] / row['cycles']
        row['speed_b0'] = b0['cycles'] / row['cycles']
        for name in tuple(row):
            if name.startswith('slots_'):
                row['delta_' + name] = row[name] - b0[name]
    write(rows)


if __name__ == '__main__':
    main()
