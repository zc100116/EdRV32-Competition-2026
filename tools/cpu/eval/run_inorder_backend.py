#!/usr/bin/env python3
# File: run_inorder_backend.py; Spec: cpu-spec 2.3, 4.1-4.4 and C-E9 B9-B13; Clock: host.
# Measure backend timing limits on B0 and the measured B8, including address load-use stalls.
# Read the completed issue matrix; write independent backend results with two model workers.
"""Run after run_inorder_max.py with the edrv32 environment sourced."""
from concurrent.futures import FIRST_COMPLETED, ProcessPoolExecutor, wait
import csv
from itertools import islice

from pipe_model import INORDER_VARIANTS, simulate
from run_inorder_max import OUT, select
from run_pipeline_analysis import CONFIGS, load

CASES = (
    ('reference', {}), ('B9', {'e_penalty': 2}), ('B10', {'d_penalty': 1}),
    ('B11-mul1', {'mul_latency': 1}), ('B11-mul2', {'mul_latency': 2}),
    ('B12-load1', {'load_latency': 1}),
)
DEFAULTS = dict(e_penalty=3, d_penalty=2, load_latency=2, mul_latency=3)


def evaluate(job):
    rvc, option, variant, case, changes, timing = job
    if variant == 'B8':
        INORDER_VARIANTS['B8'] = changes
    program, symbols, trace = load((rvc, option))
    statistics = {}
    settings = DEFAULTS | timing
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                      variant, statistics=statistics, **settings)
    print(f'RVC={rvc} {option} {variant}/{case}: {result["cycles"]} cycles, '
          f'{result["ipc"]:.6f} IPC', flush=True)
    return dict(rvc=rvc, option=option, variant=variant, case=case,
                **settings, **result, **statistics)


def write(rows):
    with (OUT / 'backend.csv').open('w') as log:
        writer = csv.DictWriter(log, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    with (OUT / 'results.csv').open() as log:
        issue = [dict(r, cycles=int(r['cycles'])) for r in csv.DictReader(log)]
    changes, components = select([r for r in issue if r['variant'] in INORDER_VARIANTS])
    print(f'B8 components: {components}; settings: {changes}', flush=True)
    jobs = iter((rvc, option, variant, case, changes, timing)
                for case, timing in CASES for variant in ('B0', 'B8')
                for rvc, option in CONFIGS)
    rows = []
    with ProcessPoolExecutor(max_workers=2) as pool:
        pending = {pool.submit(evaluate, job) for job in islice(jobs, 2)}
        while pending:
            done, pending = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                rows.append(future.result())
                write(rows)
                if job := next(jobs, None):
                    pending.add(pool.submit(evaluate, job))
    base = {(r['rvc'], r['option'], r['variant']): r['cycles'] for r in issue}
    for row in rows:
        key = str(row['rvc']), row['option']
        row['speed_v0'] = base[*key, 'V0'] / row['cycles']
        row['speed_b0'] = base[*key, 'B0'] / row['cycles']
        row['speed_reference'] = base[*key, row['variant']] / row['cycles']
        row['load_use_address_cycles'] = sum(row[k] for k in (
            'load_use_load_address_cycles', 'load_use_store_address_cycles'))
    write(rows)


if __name__ == '__main__':
    main()
