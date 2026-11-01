#!/usr/bin/env python3
"""T-NESKEY: compile real NES main/parser against deterministic UART/IRQ mocks.

Optional argument selects a saved baseline main.c to demonstrate the regression.
CPU CSR entry/exit is mocked; actual RX threshold setup, draining, parsing and
NES merging come from main.c and virtual_input.c. No LVGL build is needed.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/nes-input-host'
OUT.mkdir(parents=True, exist_ok=True)
source = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'sw/apps/nes/main.c'
flags = ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
         '-Isw/apps/nes', '-Isw/lib', '-Isw/drivers/include', '-Isw/bsp/include',
         '-include', 'sw/apps/nes/tests/input_mmio.h']
subprocess.run(flags + ['-DNES_DISPLAY=0', '-DNES_FRAMES=0', '-DNES_SKIP=0',
                       '-Dmain=nes_application_main', '-c', str(source),
                       '-o', str(OUT / 'main.o')], cwd=ROOT, check=True)
subprocess.run(flags + ['sw/apps/nes/tests/input_release.c', 'sw/lib/virtual_input.c',
                       str(OUT / 'main.o'), '-o', str(OUT / 'input-release')],
               cwd=ROOT, check=True)
subprocess.run([str(OUT / 'input-release')], cwd=ROOT, check=True)
