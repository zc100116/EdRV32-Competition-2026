#!/usr/bin/env python3
# File: run_wide_ooo_eval.py; Spec: cpu-spec 4.1-4.4; Clock: host.
# Run representative ordered/renamed configurations once on three Spike traces.
# Use a shared simulation lock externally; the pool never exceeds two models.
"""Inputs: build/wide-ooo/input/{coremark,vision,render}; calibrate first."""
from concurrent.futures import ProcessPoolExecutor
import argparse
import json
from pathlib import Path

from ooo_model import memory_trace, simulate as out_of_order
from pipe_model import program_and_trace
from wide_model import simulate as in_order

OUT = Path('build/wide-ooo')
INORDER = {
    'I2r': dict(width=2, alus=2, lsus=1, branches=1, restricted=True),
    'I2f': dict(width=2, alus=2, lsus=1, branches=1),
    'I2d': dict(width=2, alus=2, lsus=2, branches=1),
    'I3a': dict(width=3, alus=2, lsus=1, branches=1),
    'I3b': dict(width=3, alus=3, lsus=1, branches=1),
    'I3d': dict(width=3, alus=3, lsus=2, branches=1),
    'I4a': dict(width=4, alus=3, lsus=1, branches=1),
    'I4d': dict(width=4, alus=4, lsus=2, branches=2),
}
OOO_POINTS = {
    'O2a': (2, 32, 16, 1, 7), 'O2p6': (2, 32, 16, 1, 6),
    'O2p8': (2, 32, 16, 1, 8), 'O2r': (2, 64, 16, 1, 7),
    'O2q': (2, 32, 32, 1, 7), 'O2b': (2, 64, 32, 1, 7),
    'O3a': (3, 32, 16, 1, 7), 'O3b': (3, 64, 32, 1, 7),
    'O3d': (3, 64, 32, 2, 7), 'O4d': (4, 64, 32, 2, 8),
}
OOO = {name: dict(zip(('issue_width', 'rob_size', 'iq_size', 'lsus', 'penalty'), point))
       for name, point in OOO_POINTS.items()}


def load(workload):
    global PROGRAM, SYMBOLS, TRACE, ADDRESSES
    directory = OUT / 'input' / workload
    PROGRAM, SYMBOLS, TRACE = program_and_trace(directory)
    ADDRESSES = memory_trace(directory, PROGRAM, TRACE)


def evaluate(job):
    name, options = job
    args = (PROGRAM, TRACE, SYMBOLS['start_time'], SYMBOLS['stop_time'])
    if name.startswith('I'):
        result = in_order(*args, **options)
    else:
        result = out_of_order(PROGRAM, TRACE, ADDRESSES,
                              SYMBOLS['start_time'], SYMBOLS['stop_time'], **options)
    return dict(name=name, options=options, **result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('calibrate', 'scan'))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.phase == 'calibrate':
        load('coremark')
        result = evaluate(('I2r', INORDER['I2r']))
        (OUT / 'calibration.json').write_text(json.dumps(result) + '\n')
        print(json.dumps(result), flush=True)
    else:
        for workload in ('coremark', 'vision', 'render'):
            # CoreMark I2r is the calibration run, never measured a second time.
            configs = INORDER | OOO
            if workload == 'coremark':
                configs = {k: v for k, v in configs.items() if k != 'I2r'}
            with (OUT / (workload + '.jsonl')).open('w') as output:
                if workload == 'coremark':
                    output.write((OUT / 'calibration.json').read_text())
                with ProcessPoolExecutor(max_workers=2, initializer=load,
                                         initargs=(workload,)) as pool:
                    for result in pool.map(evaluate, configs.items()):
                        line = json.dumps(dict(workload=workload, **result))
                        output.write(line + '\n')
                        output.flush()
                        print(line, flush=True)


if __name__ == '__main__':
    main()
