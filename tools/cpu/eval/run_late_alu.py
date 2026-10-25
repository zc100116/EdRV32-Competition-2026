#!/usr/bin/env python3
# File: run_late_alu.py; Spec: cpu-spec 2.3, 4.1-4.4 and C-E7 assumptions; Clock: host.
# Measure four late-execution variants with and without V5 against the C-E5 baselines.
# Reuse the four CoreMark ELF/Spike inputs; run at most two model processes.
"""Source the edrv32 environment, then run from the repository root."""
from concurrent.futures import FIRST_COMPLETED, ProcessPoolExecutor, wait
import csv
from pathlib import Path

from pipe_model import simulate
from run_pipeline_analysis import CONFIGS, load

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/cpu_late_alu'
VARIANTS = ('V0', 'V2s', 'V2s+V5', 'L1', 'L1+V5', 'L2', 'L2+V5',
            'L2b', 'L2b+V5', 'L2s', 'L2s+V5')


def evaluate(job):
    rvc, option, variant = job
    program, symbols, trace = load((rvc, option))
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'], variant)
    print(f'RVC={rvc} {option} {variant}: {result["cycles"]} cycles, '
          f'{result["ipc"]:.6f} IPC, {result["late_instructions"]} late, '
          f'{result["training_conflicts"]} training conflicts', flush=True)
    return dict(rvc=rvc, option=option, variant=variant, **result)


def write(rows):
    with (OUT / 'results.csv').open('w') as log:
        writer = csv.DictWriter(log, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    work = iter((rvc, option, variant) for variant in VARIANTS for rvc, option in CONFIGS)
    rows = []
    with ProcessPoolExecutor(max_workers=2) as pool:
        pending = {pool.submit(evaluate, next(work)) for _ in range(2)}
        while pending:
            done, pending = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                rows.append(future.result())
                write(rows)
                if job := next(work, None):
                    pending.add(pool.submit(evaluate, job))
    baselines = {(r['rvc'], r['option'], r['variant']): r for r in rows
                 if r['variant'] in {'V0', 'V2s', 'V2s+V5'}}
    for row in rows:
        v0 = baselines[row['rvc'], row['option'], 'V0']
        v2s = baselines[row['rvc'], row['option'], 'V2s']
        row['speed_v0'] = v0['cycles'] / row['cycles']
        row['speed_v2s'] = v2s['cycles'] / row['cycles']
        for cause in ('pair_raw', 'load_use', 'other_result'):
            row['delta_' + cause] = row['slots_' + cause] - v2s['slots_' + cause]
    write(rows)


if __name__ == '__main__':
    main()
