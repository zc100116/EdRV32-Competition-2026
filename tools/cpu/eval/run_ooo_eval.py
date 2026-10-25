#!/usr/bin/env python3
# File: run_ooo_eval.py; Spec: cpu-spec 2.3/4.4 and C-E8; Clock: host.
# Replay four existing CoreMark ELF/Spike inputs with at most two model processes.
# Write baseline, capacity, redirect and issue-width measurements under build/.
"""Source edrv32 env; inputs default to build/cpu_ooo_eval/input."""
import argparse
from concurrent.futures import ProcessPoolExecutor
import csv
from pathlib import Path

from ooo_model import memory_trace, simulate
from pipe_model import program_and_trace, simulate as in_order

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/cpu_ooo_eval'
CONFIGS = ((1, 'o2'), (0, 'o2'), (1, 'tuned'), (0, 'tuned'))
CAPACITIES = ((32, 16), (16, 8), (32, 8), (64, 8), (64, 16), (64, 32))


def write_csv(path, rows):
    with path.open('w') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def evaluate(job):
    input_root, rvc, option = job
    directory = input_root / f'rvc{rvc}_r05_{option}'
    program, symbols, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace)
    begin, end = symbols['start_time'], symbols['stop_time']
    baselines = []
    for variant in ('V0', 'V2s', 'V2s+V5'):
        row = dict(rvc=rvc, option=option, variant=variant,
                   **in_order(program, trace, begin, end, variant))
        baselines.append(row)
        write_csv(OUT / f'rvc{rvc}_{option}_baseline.csv', baselines)
        print(f'RVC={rvc} {option} {variant}: {row["cycles"]} cycles', flush=True)
    baseline = {row['variant']: row['cycles'] for row in baselines}
    rows = []
    points = [(rob, iq, 7, 2) for rob, iq in CAPACITIES]
    points += [(32, 16, penalty, 2) for penalty in (5, 9)]
    points += [(32, 16, 7, 3)]
    for rob, iq, penalty, width in points:
        result = simulate(program, trace, addresses, begin, end, rob_size=rob, iq_size=iq,
                          penalty=penalty, issue_width=width)
        row = dict(rvc=rvc, option=option, rob=rob, iq=iq, penalty=penalty,
                   issue_width=width, **result, v0_cycles=baseline['V0'],
                   v2s_v5_cycles=baseline['V2s+V5'],
                   speedup_v0=baseline['V0'] / result['cycles'],
                   speedup_v2s_v5=baseline['V2s+V5'] / result['cycles'])
        rows.append(row)
        write_csv(OUT / f'rvc{rvc}_{option}_ooo.csv', rows)
        print(f'RVC={rvc} {option} ROB={rob} IQ={iq} penalty={penalty} issue={width}: '
              f'{row["cycles"]} cycles {row["ipc"]:.6f} IPC '
              f'{row["speedup_v0"]:.6f}x V0 {row["speedup_v2s_v5"]:.6f}x V2s+V5',
              flush=True)
    return baselines, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=OUT / 'input')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(max_workers=2) as pool:
        groups = list(pool.map(evaluate, ((args.input, rvc, option) for rvc, option in CONFIGS)))
    write_csv(OUT / 'baseline.csv', [row for baselines, _ in groups for row in baselines])
    write_csv(OUT / 'results.csv', [row for _, rows in groups for row in rows])


if __name__ == '__main__':
    main()
