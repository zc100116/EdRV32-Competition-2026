#!/usr/bin/env python3
# File: check.py
# Spec: CLAUDE.md 7, 9.1; V-T4 independent environment acceptance.
# Description: Apply repository style rules to SV and lint the complete real GEO harness.
# Clock domain: host.
from pathlib import Path
import re
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
    subprocess.run(['python3', 'tools/check/verilog_style.py', str(HERE)],
                   cwd=ROOT, check=True)
    errors = []
    paths = sorted(HERE.glob('*.sv'))
    for path in paths:
        lines = path.read_text().splitlines()
        for error in check(path):
            _, line, message = error.rsplit(':', 2)
            message = message.strip()
            # CLAUDE 9.1 permits SV, initial blocks and delays in testbenches.
            if (message.startswith('forbidden syntax')
                    or message in ('initial block is forbidden in RTL',
                                   'delay is forbidden in RTL')):
                continue
            # The RTL instance regex also matches SV task/function declarations.
            if (message == 'use named port connections'
                    and lines[int(line) - 1].strip().startswith(('task ', 'function '))):
                continue
            errors.append(error)
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'GEO SV style: {len(paths)} files, 0 warnings', flush=True)
    out = ROOT / 'build/geo/lint'
    out.mkdir(parents=True, exist_ok=True)
    command = ['verilator', '--lint-only', '--timing', '-Wall',
               '--timescale', '1ns/1ps', '--top-module', 'edrv32_geo_tb',
               '+define+SIM_MODE', *expand_files(HERE / 'files.f')]
    with (out / 'lint.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((out / 'lint.log').read_text())
        return result.returncode
    print('GEO SV lint: 0 warnings (real DUT and full testbench)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
