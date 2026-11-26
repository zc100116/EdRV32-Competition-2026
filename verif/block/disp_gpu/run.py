#!/usr/bin/env python3
# File: run.py
# Spec: DISP testplan 3, 6; CLAUDE.md 9.1.
# Description: Build once with one job and run independent cases with selected concurrency.
# Clock domain: host.
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files  # noqa: E402
from tmds_ref import generate  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=('smoke', 'full', 'x2full'))
    parser.add_argument('--parallel', type=int, default=1)
    args = parser.parse_args()
    out = ROOT / 'build/disp_gpu'
    out.mkdir(parents=True, exist_ok=True)
    sources = expand_files(ROOT / 'verif/block/disp_gpu/files.f')
    tops = [('tb_layers', 'obj_layers')]
    if args.tier == 'full':
        tops.append(('tb', 'obj'))
    if args.tier in ('full', 'x2full'):
        tops.append(('tb_urgent', 'obj_urgent'))
    for top, directory in tops:
        started = time.monotonic()
        compile_args = ['verilator', '--binary', '--timing', '-j', '1', '-Wall',
                        '--timescale', '1ns/1ps', '-Wno-BLKSEQ', '-Wno-UNUSEDSIGNAL',
                        '-Wno-SYNCASYNCNET', '-Wno-PROCASSINIT', '-Wno-ZERODLY',
                        '--top-module', top, '--Mdir', str(out / directory),
                        '-o', 'sim', '+define+SIM_MODE', *sources]
        compile_log = out / f'{top}-compile.log'
        with compile_log.open('w') as log:
            result = subprocess.run(compile_args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        print(f'Build {top}: {time.monotonic() - started:.2f}s', flush=True)
        if result.returncode:
            print('\n'.join(line for line in compile_log.read_text().splitlines()
                            if line.startswith(('%Warning', '%Error'))))
            print(f'FAIL DISP compile {top}')
            return 1
    # D-I1 measured DS-01 and DS-03 above 60 seconds each. Keep the complete
    # original raster suites in full; smoke adds the single X2 receive/pixel case.
    # ST-04 runs every original L0-only raster, stop, reset and error case.
    cases = [(n, 1, 4096, 999, 0) for n in (1, 2, 3, 4, 5, 8, 10, 11, 12)]
    cases += [(3, 1, 2560, 999, 0)]
    cases += [(n, 1, 4096, phase, 0) for n in (10, 12) for phase in (-8, -2, 4)]
    if args.tier == 'full':
        generate(out / 'tmds.hex')
    if args.tier == 'smoke':
        cases = [(20, 1, 4096, 999, 0)]
    elif args.tier == 'x2full':
        cases = [(21, 1, 4096, 999, 0)]
    if args.tier in ('full', 'x2full'):
        if args.tier == 'full':
            cases += [(20, 1, 4096, 999, 0), (21, 1, 4096, 999, 0)]
        result = subprocess.run([str(out / 'obj_urgent/sim')], cwd=ROOT, timeout=300)
        if result.returncode:
            return 1
    def run_case(case_data):
        case, seed, stride, phase, variant = case_data
        started = time.monotonic()
        name = f'DS-{case:02d}-seed{seed}-stride{stride}'
        if phase != 999:
            name += f'-phase{phase}'
        layers = case in (20, 21)
        if layers:
            name += f'-variant{variant}'
        executable = out / ('obj_layers' if layers else 'obj') / 'sim'
        with (out / (name + '.log')).open('w') as log:
            result = subprocess.run([str(executable), f'+CASE={case}',
                                        f'+SEED={seed}', f'+STRIDE={stride}',
                                        f'+STOP_PHASE={phase}', f'+VARIANT={variant}',
                                        f'+REF={out / "tmds.hex"}'], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=600)
        output = (out / (name + '.log')).read_text()
        passed = result.returncode == 0 and 'PASS' in output and 'FAIL' not in output
        print(f'{"PASS" if passed else "FAIL"} {name} '
              f'{time.monotonic() - started:.2f}s', flush=True)
        if not passed:
            print(output, flush=True)
        return int(not passed)

    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        failures = sum(executor.map(run_case, cases))
    print(f'DISP {args.tier}: {len(cases)-failures} passed, {failures} failed')
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
