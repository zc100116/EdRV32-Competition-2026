#!/usr/bin/env python3
# File: run.py
# Spec: geo-testplan 6; CLAUDE.md 9.1.
# Description: Compile the real DUT once with one job, then generate/run cases serially.
# Clock domain: host.
import argparse
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files
from vectors import generate, selections


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=('smoke', 'full', 'perf'))
    args = parser.parse_args()
    out = ROOT / 'build/geo' / args.tier
    out.mkdir(parents=True, exist_ok=True)
    obj = ROOT / 'build/geo/obj'
    sources = expand_files(ROOT / 'verif/block/geo/files.f')
    command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
               '--timescale', '1ns/1ps', '-CFLAGS', '-O0', '--top-module', 'edrv32_geo_tb',
               '--Mdir', str(obj), '-o', 'sim', '+define+SIM_MODE', *sources]
    with (out / 'compile.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((out / 'compile.log').read_text())
        return result.returncode
    cases = selections(args.tier)
    for number, variant, seed in cases:
        name = f'GE-{number:02d}-{variant}-seed{seed}'
        directory = out / name
        config = generate(directory, number, variant, seed)
        with (directory / 'run.log').open('w') as log:
            result = subprocess.run([str(obj / 'sim'), f'+CONFIG={config}'], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=300)
        output = (directory / 'run.log').read_text()
        if result.returncode or 'PASS' not in output or 'FAIL' in output:
            print(output)
            print(f'FAIL {name}')
            return 1
        print(f'PASS {name}', flush=True)
        if number == 12:
            print('\n'.join(line for line in output.splitlines() if 'PERF0=' in line))
    print(f'PASS GEO {args.tier}: {len(cases)} cases')
    return 0


if __name__ == '__main__':
    sys.exit(main())
