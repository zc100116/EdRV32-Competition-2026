#!/usr/bin/env python3
# File: run.py
# Spec: rnd-testplan 6; CLAUDE.md 9.1; Task R-T1 acceptance.
# Description: Compile with one job, then generate and execute cases serially.
# Clock domain: host.
import argparse
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files
from vectors import generate, selections


def compile_sim(stub):
    obj = ROOT / 'build/rnd' / ('stub_obj' if stub else 'obj')
    obj.mkdir(parents=True, exist_ok=True)
    sources = expand_files(HERE / ('selftest/files.f' if stub else 'files.f'))
    command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
               '--timescale', '1ns/1ps', '--top-module', 'edrv32_rnd_tb',
               '--Mdir', str(obj), '-o', 'sim', '+define+SIM_MODE', *sources]
    with (obj / 'compile.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((obj / 'compile.log').read_text())
        raise SystemExit(result.returncode)
    return obj / 'sim'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=('smoke', 'full', 'perf', 'stub'))
    args = parser.parse_args()
    sim = compile_sim(args.tier == 'stub')
    if args.tier == 'stub':
        subprocess.run([str(sim), '+PORT_STUB'], cwd=ROOT, check=True)
        return 0
    out = ROOT / 'build/rnd' / args.tier
    cases = selections(args.tier)
    for index, (number, variant, seed) in enumerate(cases):
        name = f'RN-{number:02d}-{index:04d}-seed{seed}'
        directory = out / name
        config = generate(directory, number, variant, seed)
        with (directory / 'run.log').open('w') as log:
            result = subprocess.run([str(sim), f'+CONFIG={config}'], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        output = (directory / 'run.log').read_text()
        if result.returncode or 'PASS' not in output or 'FAIL' in output:
            print(output)
            print(f'FAIL {name} variant={variant!r}')
            return 1
        print(f'PASS {name} variant={variant!r}', flush=True)
        if number == 18:
            print('\n'.join(line for line in output.splitlines() if 'RN-18 kind=' in line))
    print(f'PASS RND {args.tier}: {len(cases)} cases')
    return 0


if __name__ == '__main__':
    sys.exit(main())
