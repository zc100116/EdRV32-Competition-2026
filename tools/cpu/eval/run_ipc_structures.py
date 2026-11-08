#!/usr/bin/env python3
# File: run_ipc_structures.py; Spec: T-CPU-IPC2; Clock: host.
# Replay each requested experimental configuration once, with at most two models.
"""Source edrv32/env.sh; run under flock -s /tmp/edrv32-sim.lock; reuse existing baselines."""
import argparse
from concurrent.futures import ProcessPoolExecutor
import json
from pathlib import Path

from ipc_structures import FUSIONS
from pipe_model import program_and_trace, simulate

OUT = Path('build/ipc-structures')
INPUTS = dict(coremark=Path('build/cpu_predictor_eval/tuned'),
              vision=Path('build/second-workloads/vision'),
              render=Path('build/second-workloads/render'))
SINGLES = {
    'lcb-M': dict(lcb='same-cycle'),
    'lcb-R': dict(lcb='registered'),
    **{'fuse-' + name: dict(fusion=(name,)) for name in FUSIONS},
    'fuse-all': dict(fusion=FUSIONS),
    'loop-cache': dict(loop_cache=True),
    'address1': dict(early_address=1),
    'address2': dict(early_address=2),
    **{'predict-' + name: dict(direction_predictor=name)
       for name in ('loop', 'tournament', 'tage')},
    'serial-any': dict(serial_alu='any'),
    'serial-simple': dict(serial_alu='simple'),
}


def load(name):
    global PROGRAM, SYMBOLS, TRACE, WORKLOAD
    WORKLOAD = name
    PROGRAM, SYMBOLS, TRACE = program_and_trace(INPUTS[name])


def evaluate(item):
    name, options = item
    result = simulate(PROGRAM, TRACE, SYMBOLS['start_time'], SYMBOLS['stop_time'],
                      'V3s', btb_entries=128, gshare_entries=4096,
                      ras_entries=4, gshare_pc_shift=2, **options)
    return dict(workload=WORKLOAD, name=name, options=options, **result)


def combinations(rows):
    baseline = dict(coremark=1877663, vision=1850040, render=505611)
    positive = [name for name in ('lcb-R', 'address1', 'serial-simple',
                                  'predict-loop', 'predict-tournament', 'predict-tage')
                if all(next(row['cycles'] for row in rows
                            if row['workload'] == work and row['name'] == name) < cycles
                       for work, cycles in baseline.items())]
    # Keep the registered LCB implementation and the best universally beneficial
    # predictor, together with the two remaining independent datapath changes.
    predictors = [name for name in positive if name.startswith('predict-')]
    best = min(predictors, key=lambda name: sum(
        row['cycles'] / baseline[row['workload']] for row in rows if row['name'] == name))
    chosen = [name for name in positive if not name.startswith('predict-')]
    small = {}
    for name in chosen:
        small.update(SINGLES[name])
    broad = dict(small, **SINGLES[best])
    return {'combo-local': small, 'combo-predict': broad,
            'combo-local-A': dict(small, e_penalty=4, d_penalty=3, mul_latency=4),
            'combo-predict-A': dict(broad, e_penalty=4, d_penalty=3, mul_latency=4)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('single', 'combine'))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.phase == 'single':
        configurations = SINGLES
    else:
        rows = [json.loads(line) for line in (OUT / 'single.jsonl').read_text().splitlines()]
        configurations = combinations(rows)
    with (OUT / (args.phase + '.jsonl')).open('w') as output:
        for workload in INPUTS:
            with ProcessPoolExecutor(max_workers=2, initializer=load,
                                     initargs=(workload,)) as pool:
                for row in pool.map(evaluate, configurations.items()):
                    line = json.dumps(row)
                    output.write(line + '\n')
                    output.flush()
                    print(line, flush=True)


if __name__ == '__main__':
    main()
