#!/usr/bin/env python3
# File: build.py
# Spec: fpu-testplan 4 FT01
# Description: Build imported Release3e RISCV reference tools under build/fpu.
# Clock: host only.
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/fpu'


def build():
    sf = ROOT / 'third_party/berkeley-softfloat-3'
    tf = ROOT / 'third_party/berkeley-testfloat-3'
    for source, target in [(sf, OUT / 'softfloat'), (tf, OUT / 'testfloat')]:
        target.mkdir(parents=True, exist_ok=True)
        for name in ['Makefile', 'platform.h']:
            shutil.copy2(source / 'build/Linux-x86_64-GCC' / name, target / name)
    subprocess.run(['make', '-s', '-C', str(OUT / 'softfloat'), '-j', '1',
                    f'SOURCE_DIR={sf}/source', 'SPECIALIZE_TYPE=RISCV',
                    'COMPILE_C=gcc -c -fPIC -O2 -DSOFTFLOAT_FAST_INT64 '
                    '-DSOFTFLOAT_ROUND_ODD -DINLINE_LEVEL=5 '
                    '-DSOFTFLOAT_FAST_DIV32TO16 -DSOFTFLOAT_FAST_DIV64TO32 '
                    f'-I. -I{sf}/source/RISCV -I{sf}/source/include -o $@'], check=True)
    subprocess.run(['make', '-s', '-C', str(OUT / 'testfloat'), '-j', '1',
                    'testfloat_gen', f'SOURCE_DIR={tf}/source', f'SOFTFLOAT_DIR={sf}',
                    f'SOFTFLOAT_LIB={OUT}/softfloat/softfloat.a',
                    'TESTFLOAT_OPTS=-DFLOAT64'], check=True)
    subprocess.run(['gcc', '-shared', '-fPIC', '-std=c11', '-Wall', '-Wextra', '-Werror',
                    '-O2', f'-I{sf}/source/include', str(ROOT / 'tools/fpu/reference.c'),
                    str(OUT / 'softfloat/softfloat.a'), '-o', str(OUT / 'reference.so')],
                   check=True)

    subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                    str(ROOT / 'tools/fpu/sample.c'), '-o', str(OUT / 'sample')], check=True)


if __name__ == '__main__':
    build()
