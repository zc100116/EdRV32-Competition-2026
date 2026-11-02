#!/usr/bin/env python3
# File: run_predictor_eval.py; Spec: cpu-spec 4.2, 4.4, 9 items 3/8; Clock: host.
# Build GCC 15.2 tuned CoreMark and scan predictor sizes on V0 and V3.
# Preserve all generated inputs and numeric measurements under build/.
"""Source the edrv32 environment; run prepare, calibrate, then scan."""
import argparse
from concurrent.futures import ProcessPoolExecutor
import csv
import importlib.util
from itertools import product
import json
from pathlib import Path
import re
import shlex
import subprocess

from pipe_model import program_and_trace, simulate
from run_coremark import ROOT, MEMORY

OUT = ROOT / 'build/cpu_predictor_eval'
TUNED = ('-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 '
         '-falign-jumps=4 -falign-loops=4')


def prepare():
    out = OUT / 'tuned'
    out.mkdir(parents=True, exist_ok=True)
    arch = 'rv32im_zicsr_zifencei'
    flags = (f'-march={arch} -mabi=ilp32 -std=c11 -Wall -Wextra -Werror {TUNED} '
             '-ffreestanding -fno-builtin -ffunction-sections -fdata-sections '
             f'-I{ROOT}/sw/bsp/include -I{ROOT}/sw/apps/coremark '
             f'-I{ROOT}/third_party/coremark -DITERATIONS=10')
    build = ['make', '-C', 'sw', 'PROGRAM=coremark', 'MEMORY=sram',
             f'OUT={out}', f'ARCH={arch}', f'CFLAGS={flags}']
    with (out / 'build.log').open('w') as log:
        subprocess.run(build, cwd=ROOT, stdout=log, stderr=log, check=True)
    elf = out / 'coremark.elf'
    symbols = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    stop = next(line.split()[0] for line in symbols.splitlines()
                if line.endswith(' T stop_time'))
    debug = out / 'debug.cmd'
    debug.write_text(f'until pc 0 {stop}\nrs 1\nquit\n')
    spike = ['spike', f'--isa={arch}_zicntr_zihpm', '--priv=m', '--pmpregions=0',
             '--no-dm', '-m' + MEMORY, '--pc=0x10000000', '--disable-dtb', '-d',
             f'--debug-cmd={debug}', '-l', '--log-commits', f'--log={out}/spike.log', str(elf)]
    (out / 'commands.txt').write_text(shlex.join(build) + '\n' + shlex.join(spike) + '\n')
    with (out / 'console.log').open('w') as log:
        subprocess.run(spike, stdout=log, stderr=log, check=True)
    with (OUT / 'versions.txt').open('w') as log:
        for command in (['git', 'rev-parse', 'HEAD'], ['riscv-none-elf-gcc', '--version'],
                        ['spike', '--help'], ['python3', '--version']):
            subprocess.run(command, stdout=log, stderr=log, check=True)


def legacy():
    snapshot = OUT / 'legacy'
    snapshot.mkdir(parents=True, exist_ok=True)
    for repo, revision, destination in ((ROOT, '7c63c3b', snapshot),
                                       (ROOT / 'third_party/coremark', 'HEAD',
                                        snapshot / 'third_party/coremark')):
        archive = OUT / 'legacy.tar'
        subprocess.run(['git', '-C', str(repo), 'archive', revision,
                        '--output=' + str(archive)], check=True)
        subprocess.run(['tar', '-xf', str(archive), '-C', str(destination)], check=True)
        archive.unlink()
    spec = importlib.util.spec_from_file_location('legacy_b2', snapshot / 'tools/cpu/b2_measure.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.OUT = ROOT / 'build/cpu_uarch_eval'
    out, elf = builder.build('r05', 0, 'tuned')
    symbols = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    stop = next(line.split()[0] for line in symbols.splitlines()
                if line.endswith(' T stop_time'))
    debug = out / 'debug.cmd'
    debug.write_text(f'until pc 0 {stop}\nrs 1\nquit\n')
    regions = json.loads((snapshot / 'rtl/include/soc_address_map.json').read_text())['regions']
    memory = ','.join(f"{r['base']}:{r['size']}" for r in regions
                      if r['name'] in ('ROM', 'SRAM'))
    command = ['spike', '--isa=rv32im_zicsr_zifencei_zicntr_zihpm', '--priv=m',
               '--pmpregions=0', '--no-dm', '-m' + memory + ',0x40007000:0x1000',
               '--pc=0x10000000', '--disable-dtb', '-d', f'--debug-cmd={debug}',
               '-l', '--log-commits', f'--log={out}/spike.log', str(elf)]
    (out / 'spike_command.txt').write_text(shlex.join(command) + '\n')
    with (out / 'console.log').open('w') as log:
        subprocess.run(command, stdout=log, stderr=log, check=True)
    program, symbols, trace = program_and_trace(out)
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'])
    (OUT / 'legacy-v0.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f"Legacy RVC=0 tuned: {result['cycles']} cycles; report: 2306322", flush=True)


def load_input():
    global PROGRAM, SYMBOLS, TRACE
    PROGRAM, SYMBOLS, TRACE = program_and_trace(OUT / 'tuned')


def evaluate(config):
    variant, btb, gshare, ras, shift = config
    row = dict(variant=variant, btb=btb, gshare=gshare, ras=ras, shift=shift,
               **simulate(PROGRAM, TRACE, SYMBOLS['start_time'], SYMBOLS['stop_time'],
                          variant, btb_entries=btb, gshare_entries=gshare, ras_entries=ras,
                          gshare_pc_shift=shift))
    row['mispredict_rate'] = row['hpm16'] / row['hpm4']
    return row


def write_csv(path, rows):
    with path.open('w') as log:
        writer = csv.DictWriter(log, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def calibrate():
    load_input()
    row = evaluate(('V0', 32, 512, 4, 1))
    (OUT / 'calibration.json').write_text(json.dumps(row, indent=2) + '\n')
    board = subprocess.check_output([
        'git', 'show', '874bbf53:tasks/win/20261102-40-coremark-gcc/artifacts/uart/g15-tuned.log'
    ], text=True)
    events = {int(k): int(v) for k, v in re.findall(r'HPM (\d+) [^:]+: (\d+)', board)}
    rows = []
    for event in range(1, 17):
        board_rate = events[event] / (1148269092 if event < 9 else 1148266737)
        model_rate = row[f'hpm{event}'] / row['cycles']
        rows.append(dict(event=event, board_rate=board_rate, model_rate=model_rate,
                         relative_error=model_rate / board_rate - 1 if board_rate else '',
                         difference_pp=100 * (model_rate - board_rate)))
    write_csv(OUT / 'calibration.csv', rows)
    print(json.dumps(row), flush=True)
    for metric in rows:
        print(json.dumps(metric), flush=True)


def scan(jobs):
    load_input()
    configs = list(product(('V0', 'V3'), (32, 64, 128, 256),
                           (512, 1024, 2048, 4096), (4, 8), (1,)))
    rows = []
    with ProcessPoolExecutor(max_workers=jobs) as pool:
        for row in pool.map(evaluate, configs):
            if not rows:
                baseline = row['cycles']
            row['speedup'] = baseline / row['cycles']
            rows.append(row)
            write_csv(OUT / 'scan.csv', rows)
            print(json.dumps(row), flush=True)
        best = best_sizes(rows)
        configs = [(variant, r['btb'], r['gshare'], r['ras'], 1) for r in best
                   for variant in ('V1', 'V2', 'V2s', 'V3s')]
        lanes = []
        for row in pool.map(evaluate, configs):
            row['speedup'] = baseline / row['cycles']
            lanes.append(row)
            write_csv(OUT / 'lanes.csv', lanes)
            print(json.dumps(row), flush=True)
        sizes = {(32, 512, 4)} | {(r['btb'], r['gshare'], r['ras']) for r in best}
        configs = [(variant, *size, 2) for size in sorted(sizes)
                   for variant in ('V0', 'V3', 'V3s')]
        indices = []
        for row in pool.map(evaluate, configs):
            row['speedup'] = baseline / row['cycles']
            indices.append(row)
            write_csv(OUT / 'indices.csv', indices)
            print(json.dumps(row), flush=True)


def storage(row):
    btb = row['btb']
    return btb * (32 - 3 - (btb.bit_length() - 1) + 32 + 1 + 3 + 1) + (
        2 * row['gshare'] + 32 * row['ras'])


def best_sizes(rows):
    # Choose the fastest RAS for each BTB/PHT size; break ties by storage.
    ranked = sorted((r for r in rows if r['variant'] == 'V3'),
                    key=lambda r: (r['cycles'], storage(r)))
    sizes = {}
    for row in ranked:
        sizes.setdefault((row['btb'], row['gshare']), row)
    return list(sizes.values())[:2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('prepare', 'calibrate', 'scan', 'legacy'))
    parser.add_argument('--jobs', type=int, default=1, help='parallel model processes')
    args = parser.parse_args()
    if args.phase == 'prepare':
        prepare()
    elif args.phase == 'calibrate':
        calibrate()
    elif args.phase == 'legacy':
        legacy()
    else:
        scan(args.jobs)


if __name__ == '__main__':
    main()
