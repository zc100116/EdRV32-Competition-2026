#!/usr/bin/env python3
# File: perf.py
# Spec: T-RND1/T-RND2 focused acceptance; rnd-spec 7.
# Description: Measure the existing COPY/BLUR/SHADOW cases with the same byte oracle.
#              A negative telemetry kind prints counters without RN-18 size thresholds.
# Clock domain: host tool.
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'verif/block/rnd'))
from vectors import generate


CASES = [(10, (0, 'dr')), (10, (1, 'dr')), (11, (1, 8, 7)), (12, (1, 8))]


def main():
    simulator = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2])
    for index, (number, variant) in enumerate(CASES):
        directory = output / f'RN-{number:02d}-{index}'
        config = generate(directory, number, variant, 1)
        lines = config.read_text().splitlines()
        fields = lines[0].split()
        fields[9] = str(-number)
        lines[0] = ' '.join(fields)
        config.write_text('\n'.join(lines) + '\n')
        with (directory / 'run.log').open('w') as log:
            subprocess.run([str(simulator), '+CONFIG=' + str(config)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        print(f'RN-{number:02d} variant={variant!r}', flush=True)
        for line in (directory / 'run.log').read_text().splitlines():
            if 'PERF0=' in line or 'PASS' in line:
                print(line, flush=True)


if __name__ == '__main__':
    main()
