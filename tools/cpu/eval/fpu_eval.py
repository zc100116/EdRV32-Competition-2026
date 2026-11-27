#!/usr/bin/env python3
# fpu_eval.py — C2-F design evaluation; compile C, trace Spike, replay FPU timings.
# Design: docs/design/2026-11-27-cpu-v2-fpu.md. Clock: host.
"""Run serially after sourcing ~/.local/opt/edrv32/env.sh; outputs in build/c2f."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import shlex
import subprocess

from fpu_model import SCHEMES, decode, simulate

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'workloads/fp'
OUT = ROOT / 'build/c2f'
WORKLOADS = ('matrix_s', 'matrix_d', 'whetstone_s', 'whetstone_d', 'vertex_s', 'physics_s')
ARCHES = {'soft': ('rv32im', 'ilp32'), 'F': ('rv32imf', 'ilp32f'),
          'FD': ('rv32imfd', 'ilp32d')}
DISASM = re.compile(r'^\s*([0-9a-f]+):\s+([0-9a-f]+)\s+(\S+)\s*(.*)$')
COMMIT = re.compile(r'^core\s+\d+:\s+3\s+0x([0-9a-f]+)\s+\(0x[0-9a-f]+\)')


def run(command, log):
    with log.open('w') as stream:
        subprocess.run(command, stdout=stream, stderr=stream, check=True)


def build_trace(workload, arch):
    out = OUT / workload / arch
    out.mkdir(parents=True, exist_ok=True)
    march, abi = ARCHES[arch]
    march += '_zicsr_zifencei'
    source = SOURCE / ('whetstone.c' if workload.startswith('whetstone') else 'kernels.c')
    workload_id = {'matrix': 0, 'vertex': 1, 'physics': 2, 'whetstone': 3}[workload.split('_')[0]]
    command = ['riscv-none-elf-gcc', '-march=' + march, '-mabi=' + abi,
               '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-ffp-contract=fast',
               '-fno-math-errno', '-ffreestanding', '-ffunction-sections', '-fdata-sections',
               '-DWORKLOAD=' + str(workload_id)]
    if workload.endswith('_s'):
        command += ['-DSINGLE']
    if arch != 'soft':
        command += ['-DFP_ENABLED']
    command += [str(SOURCE / 'start.S'), str(source), '-nostdlib', '-Wl,--gc-sections',
                '-T' + str(HERE / 'workloads/spike.ld'), '-lm', '-lc', '-lgcc',
                '-o', str(out / 'workload.elf')]
    run(command, out / 'build.log')
    symbols = subprocess.check_output(['riscv-none-elf-nm', str(out / 'workload.elf')], text=True)
    symbols = {s[2]: int(s[0], 16) for line in symbols.splitlines() if len(s := line.split()) == 3}
    (out / 'debug.cmd').write_text(f"until pc 0 {symbols['stop_time']:x}\nquit\n")
    spike = ['spike', '--isa=' + march, '--priv=m', '--pmpregions=0', '--no-dm',
             '-m0x80000000:0x2000000', '--pc=0x80000000', '--disable-dtb', '-d',
             '--debug-cmd=' + str(out / 'debug.cmd'), '-l', '--log-commits',
             '--log=' + str(out / 'spike.log'), str(out / 'workload.elf')]
    (out / 'commands.txt').write_text(shlex.join(command) + '\n' + shlex.join(spike) + '\n')
    run(spike, out / 'console.log')


def measure(workload, arch):
    out = OUT / workload / arch
    elf = out / 'workload.elf'
    disasm = subprocess.check_output(['riscv-none-elf-objdump', '-d', '-M', 'no-aliases,numeric',
                                     str(elf)], text=True)
    (out / 'numeric.dis').write_text(disasm)
    program = {int(m[1], 16): decode(int(m[1], 16), m[3], m[4])
               for line in disasm.splitlines() if (m := DISASM.match(line))}
    symbols = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    symbols = {s[2]: int(s[0], 16) for line in symbols.splitlines() if len(s := line.split()) == 3}
    trace = []
    active = False
    with (out / 'spike.log').open() as log:
        for line in log:
            if m := COMMIT.match(line):
                pc = int(m[1], 16)
                if pc == symbols['start_time']:
                    active = True
                if pc == symbols['stop_time']:
                    break
                if active:
                    trace.append(pc)
    if not trace:
        raise RuntimeError(f'No timed Spike commits in {out}')
    size = subprocess.check_output(['riscv-none-elf-size', str(elf)], text=True)
    (out / 'size.txt').write_text(size)
    counts = [int(v) for v in size.splitlines()[1].split()[:3]]
    if arch == 'soft':
        baseline = simulate(program, trace)
        results = {scheme: baseline for scheme in SCHEMES}
    else:
        results = {scheme: simulate(program, trace, scheme) for scheme in SCHEMES}
    results['bypass_3r'] = (baseline if arch == 'soft'
                            else simulate(program, trace, 'bypass', reads=3))
    results['bypass_q4'] = simulate(program, trace, 'bypass', queue_depth=4)
    result = dict(workload=workload, arch=arch, text=counts[0], data=counts[1], bss=counts[2],
                  operations=dict(Counter(program[pc].name for pc in trace)), estimates=results)
    (out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('run', 'measure'))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for workload in WORKLOADS:
        for arch in ARCHES:
            if args.phase == 'run':
                build_trace(workload, arch)
            row = measure(workload, arch)
            rows.append(row)
            print(workload, arch, row['text'], row['estimates']['bypass']['cycles'], flush=True)
    metadata = dict(commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                    gcc=subprocess.check_output(
                        ['riscv-none-elf-gcc', '--version'], text=True).splitlines()[0],
                    rows=rows)
    (OUT / 'results.json').write_text(json.dumps(metadata, indent=2) + '\n')
    lines = ['|负载|text soft/F/FD (B)|soft 周期|F 周期/加速|FD 周期/加速|',
             '|---|---:|---:|---:|---:|']
    for workload in WORKLOADS:
        group = [r for r in rows if r['workload'] == workload]
        cycles = [r['estimates']['bypass']['cycles'] for r in group]
        sizes = '/'.join(str(r['text']) for r in group)
        lines.append(f'|{workload}|{sizes}|{cycles[0]}|{cycles[1]} / {cycles[0]/cycles[1]:.2f}×|'
                     f'{cycles[2]} / {cycles[0]/cycles[2]:.2f}×|')
    (OUT / 'table.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
