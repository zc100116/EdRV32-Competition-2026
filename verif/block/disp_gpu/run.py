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
from blend_ref import generate as generate_blend, self_test  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=('smoke', 'full', 'slim1', 'x2full'))
    parser.add_argument('--parallel', type=int, default=1)
    args = parser.parse_args()
    out = ROOT / 'build/disp_gpu'
    out.mkdir(parents=True, exist_ok=True)
    if args.tier != 'slim1':
        self_test()
    sources = expand_files(ROOT / 'verif/block/disp_gpu/files.f')
    tops = [('tb_layers', 'obj_layers')]
    if args.tier in ('full', 'slim1'):
        tops.append(('tb', 'obj'))
    if args.tier in ('full', 'x2full'):
        tops.append(('tb_urgent', 'obj_urgent'))
    if args.tier == 'full':
        tops.append(('tb_blend_ref', 'obj_ref'))
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
    cases = [(n, 1, 4096, 999, 0) for n in (1, 3, 4, 5, 11, 12)]
    cases.insert(1, (3, 1, 2560, 999, 0))
    cases += [(12, 1, 4096, phase, 0) for phase in (-8, -2, 4)]
    cases += [(6, 1, 4096, 999, 0), (12, 1, 4096, 999, 1)]
    cases += [(7, 1, 4096, 999, v) for v in range(3)]
    cases += [(14, 1, 4096, 999, v) for v in (*range(16), 16, 31, 48)]
    cases += [(15, 1, 4096, 999, 0)]
    cases += [(16, 1, 4096, 999, v) for v in range(3)]
    cases += [(17, 1, 4096, 999, 0)]
    if args.tier == 'full':
        generate(out / 'tmds.hex')
    cases += [(n, 1, 4096, 999, 0) for n in (2, 8, 9, 10, 19)]
    cases += [(10, 1, 4096, phase, 0) for phase in (-8, -2, 4)]
    cases += [(13, seed, 4096, 999, 0) for seed in range(1, 11)]
    cases += [(18, 1, 4096, 999, v) for v in range(18)]
    if args.tier == 'slim1':
        cases = [(7, 1, 4096, 999, 2), (8, 1, 4096, 999, 0),
                 (9, 1, 4096, 999, 0)]
    if args.tier == 'full':
        started = time.monotonic()
        generate_blend(out / 'blend.hex')
        with (out / 'blend-ref-sv.log').open('w') as log:
            result = subprocess.run([str(out / 'obj_ref/sim'),
                                        f'+BLEND_REF={out / "blend.hex"}'], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=300)
        reference_result = (out / 'blend-ref-sv.log').read_text()
        print(reference_result, flush=True)
        print(f'Blend reference: {time.monotonic() - started:.2f}s', flush=True)
        if result.returncode:
            return 1
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
        layers = (case in (20, 21, 6, 7, 9, 13, 14, 15, 16, 17, 18, 19) or
                    (case == 12 and variant == 1))
        if layers:
            name += f'-variant{variant}'
        executable = out / ('obj_layers' if layers else 'obj') / 'sim'
        with (out / (name + '.log')).open('w') as log:
            result = subprocess.run([str(executable), f'+CASE={case}',
                                        f'+SEED={seed}', f'+STRIDE={stride}',
                                        f'+STOP_PHASE={phase}', f'+VARIANT={variant}',
                                        f'+BLEND_REF={out / "blend.hex"}',
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
