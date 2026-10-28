#!/usr/bin/env python3
# File: run.py
# Spec: DISP testplan 3, 6; CLAUDE.md 9.1.
# Description: Build once with one job and execute each selected case serially.
# Clock domain: host.
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files  # noqa: E402
from tmds_ref import generate  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=('smoke', 'full'))
    args = parser.parse_args()
    out = ROOT / 'build/disp'
    out.mkdir(parents=True, exist_ok=True)
    sources = expand_files(ROOT / 'verif/block/disp/files.f')
    compile_args = ['verilator', '--binary', '--timing', '-j', '1', '-Wall',
                    '--timescale', '1ns/1ps', '-Wno-BLKSEQ', '-Wno-UNUSEDSIGNAL',
                    '-Wno-SYNCASYNCNET', '--top-module', 'tb', '--Mdir', str(out / 'obj'), '-o', 'sim',
                    '+define+SIM_MODE', *sources]
    with (out / 'compile.log').open('w') as log:
        result = subprocess.run(compile_args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join(line for line in (out / 'compile.log').read_text().splitlines()
                        if line.startswith(('%Warning', '%Error'))))
        print('FAIL DISP compile')
        return 1
    cases = [(n, 1, 4096, 999) for n in (1, 3, 4, 5, 6, 7, 11, 12)]
    cases.insert(1, (3, 1, 2560, 999))
    cases += [(12, 1, 4096, phase) for phase in (-8, -2, 4)]
    if args.tier == 'full':
        generate(out / 'tmds.hex')
        cases = [(n, 1, 4096, 999) for n in (2, 8, 9, 10)]
        cases += [(10, 1, 4096, phase) for phase in (-8, -2, 4)]
        cases += [(13, seed, 4096, 999) for seed in range(1, 11)]
    failures = 0
    for case, seed, stride, phase in cases:
        name = f'DS-{case:02d}-seed{seed}-stride{stride}'
        if phase != 999:
            name += f'-phase{phase}'
        with (out / (name + '.log')).open('w') as log:
            result = subprocess.run([str(out / 'obj/sim'), f'+CASE={case}',
                                     f'+SEED={seed}', f'+STRIDE={stride}',
                                     f'+STOP_PHASE={phase}',
                                     f'+REF={out / "tmds.hex"}'], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=300)
        output = (out / (name + '.log')).read_text()
        passed = result.returncode == 0 and 'PASS' in output and 'FAIL' not in output
        print(f'{"PASS" if passed else "FAIL"} {name}', flush=True)
        if not passed:
            print(output, flush=True)
            failures += 1
    print(f'DISP {args.tier}: {len(cases)-failures} passed, {failures} failed')
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
