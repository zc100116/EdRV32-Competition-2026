#!/usr/bin/env python3
# File: run_coremark.py; Spec: cpu-plan C-E1; Clock: host.
# Build the six requested ISA variants from the P0 port and retain Spike logs.
"""Run from the repository root after sourcing the edrv32 tool environment."""
from pathlib import Path
import shlex
import subprocess

VARIANTS = ('rv32im', 'rv32imc', 'rv32im_zba_zbb', 'rv32imc_zba_zbb',
            'rv32im_zba', 'rv32imc_zba')
ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / 'build/cpu/eval'


def run():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with (OUTPUT / 'versions.txt').open('w') as log:
        for command in (['git', 'rev-parse', 'HEAD'], ['git', 'submodule', 'status',
                         'third_party/coremark'], ['riscv-none-elf-gcc', '--version'],
                        ['riscv-none-elf-objdump', '--version'], ['spike', '--help'],
                        ['python3', '--version']):
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=log, check=True)
    for variant in VARIANTS:
        out = OUTPUT / variant
        out.mkdir(parents=True, exist_ok=True)
        # CSR timing is part of the existing P0 port, common to all six variants.
        arch = variant + '_zicsr'
        flags = (f'-march={arch} -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 '
                 '-ffreestanding -fno-builtin -ffunction-sections -fdata-sections '
                 f'-I{ROOT}/sw/bsp/include -I{ROOT}/sw/apps/coremark '
                 f'-I{ROOT}/third_party/coremark -DITERATIONS=10')
        build = ['make', '-C', 'sw', 'PROGRAM=coremark', 'MEMORY=sram',
                 f'OUT={out}', f'ARCH=-march={arch} -mabi=ilp32', f'CFLAGS={flags}']
        elf = out / 'coremark.elf'
        spike = ['spike', f'--isa={arch}_zifencei_zicntr_zihpm', '--priv=m',
                 '--pmpregions=0', '--no-dm', '-m0:0x4000,0x10000000:0x40000',
                 '--pc=0x10000000', '--disable-dtb', '-l', '--log-commits',
                 f'--log={out}/spike.log', str(elf)]
        (out / 'commands.txt').write_text(shlex.join(build) + '\n' + shlex.join(spike) + '\n')
        with (out / 'build.log').open('w') as log:
            subprocess.run(build, cwd=ROOT, stdout=log, stderr=log, check=True)
        with (out / 'console.log').open('w') as log:
            subprocess.run(spike, cwd=ROOT, stdout=log, stderr=log, check=True)
        print(f'Completed {variant}', flush=True)


if __name__ == '__main__':
    run()
