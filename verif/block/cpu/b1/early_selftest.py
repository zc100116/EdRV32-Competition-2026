#!/usr/bin/env python3
# File: early_selftest.py; Spec: cpu-testplan A-02/A-03; Clock: host.
# Description: Compile and exercise the speculative D$ model without CPU RTL.
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]


def main():
    out = ROOT / 'build/cpu-early-selftest'
    out.mkdir(parents=True, exist_ok=True)
    b1 = Path(__file__).resolve().parent
    sources = [b1 / name for name in ('edrv32_cpu_memory.sv', 'edrv32_cpu_dc_model.sv',
                                     'edrv32_cpu_early_tb.sv')]
    with (out / 'compile.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                        '--top-module', 'edrv32_cpu_early_tb',
                        '+incdir+' + str(ROOT / 'rtl/include'), '--Mdir', str(out / 'obj'),
                        '-o', 'sim', *map(str, sources)], stdout=log, stderr=log, check=True)
    with (out / 'run.log').open('w') as log:
        subprocess.run([str(out / 'obj/sim')], stdout=log, stderr=log, check=True)
    print((out / 'run.log').read_text(), end='')


if __name__ == '__main__':
    main()
