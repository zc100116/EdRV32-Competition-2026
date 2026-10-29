#!/usr/bin/env python3
# File: check.py
# Spec: CLAUDE.md 7, 9.1; Task R-T1 acceptance.
# Description: Apply repository structural style to verification SV and lint public-port stub.
# Clock domain: host.
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/check'))
from regress import expand_files
from verilog_style import check


def main():
    errors = []
    paths = sorted(HERE.rglob('*.sv'))
    for path in paths:
        lines = path.read_text().splitlines()
        for error in check(path):
            _, line, message = error.rsplit(':', 2)
            message = message.strip()
            # CLAUDE 9.1 explicitly permits SystemVerilog, stimulus and clocks in verif/.
            if (message.startswith('forbidden syntax')
                    or message in ('initial block is forbidden in RTL',
                                   'delay is forbidden in RTL')):
                continue
            if (message == 'use named port connections'
                    and lines[int(line) - 1].strip().startswith(('task ', 'function '))):
                continue
            errors.append(error)
    for path in HERE.rglob('*.py'):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if '\t' in line or len(line) > 100:
                errors.append(f'{path}:{number}: Tab or line exceeds 100 columns')
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'RND style: {len(paths)} SV files, Python sources, 0 warnings', flush=True)
    out = ROOT / 'build/rnd/lint'
    out.mkdir(parents=True, exist_ok=True)
    command = ['verilator', '--lint-only', '--timing', '-Wall',
               '--timescale', '1ns/1ps', '--top-module', 'edrv32_rnd_tb',
               '+define+SIM_MODE', *expand_files(HERE / 'selftest/files.f')]
    with (out / 'lint.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((out / 'lint.log').read_text())
        return result.returncode
    print('PASS RND lint: 0 warnings (public-port stub and complete testbench)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
