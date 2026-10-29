#!/usr/bin/env python3
# File: run.py
# Spec: Task B3-9 acceptance; CLAUDE.md 9.1.
# Description: Lint the real board top, then run control and SCCB unit tests serially.
# Clock domain: none (host tool).
"""Run the CPU-free image-path board unit tests without full-frame SoC simulation."""
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/fpga_imgtest'


def command(args, name):
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / name).open('w') as log:
        subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)


def lint_top():
    command(['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
             '--top-module', 'edrv32_fpga_board_imgtest_top'] +
            expand_files(HERE / 'top_files.f'), 'top_lint.log')
    print('PASS fpga_imgtest top lint: 0 warnings', flush=True)


def main():
    start = time.monotonic()
    camera_only = '--camera' in sys.argv
    if not camera_only:
        lint_top()
    if len(sys.argv) > 1 and sys.argv[1] == '--lint-only':
        return
    table = (ROOT / 'sw/drivers/ov5640.c').read_text().split('/* Design 3.2')[0]
    entries = re.findall(r'\{0x([0-9a-f]+)u, 0x([0-9a-f]+)u\}', table)
    camera_table = OUT / 'camera_expected.hex'
    camera_table.write_text(''.join(address + value + '\n' for address, value in entries))
    for kind in (['cam'] if camera_only else ['ctrl']):
        top = f'edrv32_fpga_imgtest_{kind}_tb'
        sources = expand_files(HERE.parent / f'fpga_imgtest_{kind}' / 'files.f')
        common = ['--timing', '-Wall', '+define+SIM_MODE', '--top-module', top] + sources
        command(['verilator', '--lint-only'] + common, f'{kind}_lint.log')
        obj = OUT / f'obj_{kind}'
        command(['verilator', '--binary', '-j', '1', '-CFLAGS', '-O1',
                 '--Mdir', str(obj), '-o', 'sim'] + common, f'{kind}_compile.log')
        command([str(obj / 'sim'), '+CAM_TABLE=' + str(camera_table)], f'{kind}_simulation.log')
        log = (OUT / f'{kind}_simulation.log').read_text()
        if f'PASS fpga_imgtest_{kind}' not in log:
            raise RuntimeError(f'{kind}: missing PASS in {OUT}')
        print(log.strip(), flush=True)
    print(f'PASS fpga_imgtest elapsed={time.monotonic() - start:.2f}s', flush=True)


if __name__ == '__main__':
    main()
