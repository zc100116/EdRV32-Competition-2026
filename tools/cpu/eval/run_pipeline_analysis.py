#!/usr/bin/env python3
# File: run_pipeline_analysis.py; Spec: cpu-spec 2.3, 4.1-4.4; Clock: host.
# Measure the C-E5 restricted branch lane, mutually exclusive issue slots and timing limits.
# Reuse C-E4 ELF/Spike inputs; run at most two models and retain numeric results in build/.
"""Source the edrv32 environment, then run from the repository root."""
from concurrent.futures import FIRST_COMPLETED, ProcessPoolExecutor, wait
import csv
from functools import cache
from pathlib import Path

from pipe_model import program_and_trace, simulate

ROOT = Path(__file__).resolve().parents[3]
INPUT = ROOT / 'build/cpu_uarch_eval'
OUT = ROOT / 'build/cpu_pipeline_analysis'
CONFIGS = ((1, 'o2'), (0, 'o2'), (1, 'tuned'), (0, 'tuned'))
DEFAULTS = dict(e_penalty=3, d_penalty=2, load_latency=2, mul_latency=3,
                perfect_prediction=False, perfect_frontend=False,
                relax_raw=False, all_slot1_types=False)
IDEALS = (('perfect_prediction', dict(perfect_prediction=True)),
          ('load_1', dict(load_latency=1)), ('mul_1', dict(mul_latency=1)),
          ('perfect_frontend', dict(perfect_frontend=True)),
          ('relax_raw', dict(relax_raw=True)), ('all_slot1', dict(all_slot1_types=True)))
SENSITIVITY = (('e_2', dict(e_penalty=2)), ('e_4', dict(e_penalty=4)),
               ('d_1', dict(d_penalty=1)), ('d_3', dict(d_penalty=3)),
               ('load_3', dict(load_latency=3)), ('mul_2', dict(mul_latency=2)),
               ('mul_4', dict(mul_latency=4)))


@cache
def load(config):
    rvc, option = config
    return program_and_trace(INPUT / f'rvc{rvc}_r05_{option}')


def evaluate(job):
    rvc, option, family, variant, case, changes = job
    program, symbols, trace = load((rvc, option))
    settings = DEFAULTS | changes
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                      variant, **settings)
    row = dict(rvc=rvc, option=option, family=family, variant=variant, case=case,
               **settings, **result)
    print(f'RVC={rvc} {option} {variant} {family}/{case}: '
          f'{result["cycles"]} cycles, {result["ipc"]:.6f} IPC', flush=True)
    return row


def jobs():
    cases = [('baseline', variant, 'default', {}) for variant in ('V0', 'V2s', 'V2s+V5')]
    cases += [('ideal', variant, name, changes) for variant in ('V0', 'V2s+V5')
              for name, changes in IDEALS]
    cases += [('sensitivity', 'V2s+V5', name, changes) for name, changes in SENSITIVITY]
    return iter((rvc, option, family, variant, name, changes)
                for family, variant, name, changes in cases for rvc, option in CONFIGS)


def write(rows):
    with (OUT / 'results.csv').open('w') as log:
        writer = csv.DictWriter(log, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    work = jobs()
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
    baselines = {(row['rvc'], row['option'], row['variant']): row['cycles']
                 for row in rows if row['family'] == 'baseline'}
    for row in rows:
        reference = 'V0' if row['family'] == 'baseline' else row['variant']
        row['reference_cycles'] = baselines[row['rvc'], row['option'], reference]
        row['speedup'] = row['reference_cycles'] / row['cycles']
        row['cycles_saved'] = row['reference_cycles'] - row['cycles']
    write(rows)


if __name__ == '__main__':
    main()
