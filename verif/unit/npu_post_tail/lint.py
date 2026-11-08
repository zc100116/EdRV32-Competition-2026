#!/usr/bin/env python3
# File: lint.py
# Spec: npu-spec 5.6; CLAUDE.md 7, 9.1.
# Description: Reproduce both complete SoC and FPGA board SIM_MODE -Wall lint checks.
# Clock domain: host tool.
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

OUT = ROOT / 'build/npu_post'
OUT.mkdir(parents=True, exist_ok=True)
for top, lists, extra in [
        ('edrv32_soc_top', ['rtl/filelists/soc.f'], []),
        ('edrv32_fpga_board_full_top',
         ['verif/soc/board_vnpu/files.f', 'rtl/filelists/rnd.f'],
         ['fpga/rtl/edrv32_fpga_board_full_top.v'])]:
    sources = []
    for file in lists:
        sources += expand_files(ROOT / file)
    sources += extra
    with (OUT / f'{top}-lint.log').open('w') as log:
        subprocess.run(['verilator', '--lint-only', '--timing', '-Wall', '-j', '1',
                        '+define+SIM_MODE', '--top-module', top]
                       + list(dict.fromkeys(sources)), cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    print(top, 'PASS lint')
