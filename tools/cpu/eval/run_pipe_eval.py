#!/usr/bin/env python3
# File: run_pipe_eval.py; Spec: cpu-spec 2.3, 4.1-4.4; Clock: host.
# Rebuild the C-I3 CoreMark ELFs, capture Spike commits, and run the C-E4 matrix.
# All generated traces and numeric results remain under build/cpu_uarch_eval.
"""Source the edrv32 environment; run --prepare once, then run without arguments."""
import argparse
from concurrent.futures import ProcessPoolExecutor
import csv
from pathlib import Path
import shlex
import subprocess
import sys

from pipe_model import VARIANTS, program_and_trace, simulate

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/cpu_uarch_eval'
sys.path.insert(0, str(ROOT / 'tools/cpu'))
import b2_measure  # noqa: E402


def prepare():
    b2_measure.OUT = OUT
    OUT.mkdir(parents=True, exist_ok=True)
    for rvc in (1, 0):
        for option in ('o2', 'tuned'):
            out, elf = b2_measure.build('r05', rvc, option)
            symbols = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
            stop = next(line.split()[0] for line in symbols.splitlines()
                        if line.endswith(' T stop_time'))
            debug = out / 'debug.cmd'
            # Stop before console output; the B2 host has no Spike fromhost symbol.
            debug.write_text(f'until pc 0 {stop}\nrs 1\nquit\n')
            arch = 'rv32im' + ('c' if rvc else '') + '_zicsr_zifencei_zicntr_zihpm'
            command = ['spike', f'--isa={arch}', '--priv=m', '--pmpregions=0', '--no-dm',
                       '-m0:0x4000,0x10000000:0x40000,0x40007000:0x1000',
                       '--pc=0x10000000', '--disable-dtb', '-d', f'--debug-cmd={debug}',
                       '-l', '--log-commits', f'--log={out}/spike.log', str(elf)]
            (out / 'spike_command.txt').write_text(shlex.join(command) + '\n')
            with (out / 'spike_console.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=log, check=True)
            print(f'Prepared RVC={rvc} {option}', flush=True)


def evaluate(config):
    rvc, option = config
    out = OUT / f'rvc{rvc}_r05_{option}'
    program, symbols, trace = program_and_trace(out)
    rows = []
    for variant in VARIANTS:
        row = dict(rvc=rvc, option=option, variant=variant,
                   **simulate(program, trace, symbols['start_time'], symbols['stop_time'], variant))
        if not rows:
            baseline = row['cycles']
        row['speedup'] = baseline / row['cycles']
        rows.append(row)
        with (out / 'pipe.csv').open('w') as log:
            writer = csv.DictWriter(log, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        print(f'RVC={rvc} {option} {variant}: {row["cycles"]} cycles '
              f'{row["ipc"]:.6f} IPC {row["speedup"]:.6f}x', flush=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    args = parser.parse_args()
    if args.prepare:
        prepare()
        return
    with ProcessPoolExecutor(max_workers=4) as pool:
        groups = list(pool.map(evaluate, ((1, 'o2'), (1, 'tuned'), (0, 'o2'), (0, 'tuned'))))
    rows = [row for group in groups for row in group]
    with (OUT / 'variants.csv').open('w') as log:
        writer = csv.DictWriter(log, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


if __name__ == '__main__':
    main()
