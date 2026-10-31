#!/usr/bin/env python3
# File: baseline.py
# Spec: rnd-testplan 6; T-RND2V baseline acceptance on ffb308aa.
# Description: Execute unchanged legacy cases or verify v2 OP rejection by old RTL.
# Clock domain: host.
import argparse
import subprocess
import sys

sys.dont_write_bytecode = True
from run import ROOT, SMOKE_CASES, compile_sim
from vectors import generate, selections


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=('smoke', 'perf', 'new'))
    args = parser.parse_args()
    sim = compile_sim(False)
    cases = SMOKE_CASES if args.tier == 'smoke' else (
        [case for case in selections('perf') if case[0] == 18] if args.tier == 'perf' else
        [(21, ('shared', 1), 1), (22, ('diagonal', 1, 3), 1),
         (23, ('full', 1, 3), 1), (24, (1, 0, 128), 1),
         (26, ('rotate90', 0, 1, 1, 0), 1)])
    for index, (number, variant, seed) in enumerate(cases):
        directory = ROOT / 'build/rnd/baseline' / args.tier / f'RN-{number:02d}-{index}'
        config = generate(directory, number, variant, seed)
        command = [str(sim), f'+CONFIG={config}']
        if args.tier == 'new':
            command.append('+BASELINE_ILLEGAL')
        with (directory / 'run.log').open('w') as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=1800)
        output = (directory / 'run.log').read_text()
        if result.returncode or 'PASS' not in output or 'FAIL' in output:
            print(output)
            return 1
        print(f'PASS baseline {args.tier} RN-{number:02d} {variant!r}', flush=True)
        for line in output.splitlines():
            if 'RN-18 kind=' in line or 'baseline illegal' in line:
                print(line, flush=True)
    print(f'PASS baseline {args.tier}: {len(cases)} cases')
    return 0


if __name__ == '__main__':
    sys.exit(main())
