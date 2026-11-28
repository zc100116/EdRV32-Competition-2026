#!/usr/bin/env python3
# File: run.py
# Spec: fpu-testplan FT01; CLAUDE.md 9.1.
# Description: Build reference, assert known values, generate smoke, test SV reader.
# Clock: host only.
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools/fpu'))
from build import ROOT, OUT, build
from generate import generate
from reference import instruction
from check import check
from streams import check_streams

build()
check()
check_streams()
generate('smoke', 'F', OUT / 'smoke-f')
generate('smoke', 'FD', OUT / 'smoke-fd')
vector_path = OUT / 'reader-check.vec'
vector_path.write_text(f'{instruction("madd", 32, 0):08x} 0 '
                       '000000003f800001 000000003f7ffffe 00000000bf800000 '
                       '00000000 00000000a8800000 00 0\n')
subprocess.run(['verilator', '--lint-only', '-Wall', '--timing', '--top-module', 'tb',
                str(ROOT / 'verif/common/fpu_vectors/edrv32_fpu_vectors_pkg.sv'),
                str(ROOT / 'verif/unit/fpu_ref_check/tb.sv')], check=True)
subprocess.run(['verilator', '--binary', '-Wall', '--timing', '-j', '1',
                '--top-module', 'tb', '--Mdir', str(OUT / 'reader-obj'),
                str(ROOT / 'verif/common/fpu_vectors/edrv32_fpu_vectors_pkg.sv'),
                str(ROOT / 'verif/unit/fpu_ref_check/tb.sv')], check=True)
subprocess.run([str(OUT / 'reader-obj/Vtb'), f'+VECTORS={vector_path}'], check=True)
print('PASS F05 independent reference and vector smoke')
