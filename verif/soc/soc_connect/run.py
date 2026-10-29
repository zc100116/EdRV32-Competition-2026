#!/usr/bin/env python3
# File: run.py
# Spec: B2-1a connection smoke; CLAUDE.md 9.1, 9.2.
# Description: Build the ROM/SRAM software with sw/Makefile and run the full SoC bench.
#              Keep the exact commands, compile output and UART/SIM_EXIT log in build/.
# Clock domain: none (host tool).
"""Run the B2 full-SoC connection smoke with preloaded software."""
from pathlib import Path
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/soc_connect'


def command(args, log):
    with log.open('w') as output:
        output.write(shlex.join(args) + '\n')
        output.flush()
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def pack_image(source, target):
    # sw/Makefile emits byte images; the boot ROM and SRAM models store 64-bit words.
    words = {}
    address = 0
    for token in source.read_text().split():
        if token.startswith('@'):
            address = int(token[1:], 16)
        else:
            word = address // 8
            words[word] = words.get(word, 0) | (int(token, 16) << (8 * (address % 8)))
            address += 1
    lines = []
    previous = -2
    for address, value in sorted(words.items()):
        if address != previous + 1:
            lines.append(f'@{address:x}')
        lines.append(f'{value:016x}')
        previous = address
    target.write_text('\n'.join(lines) + '\n')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    command(['make', '-C', 'sw', 'PROGRAM=soc_connect_boot', 'MEMORY=rom',
             'PROGRAM_BSP=verif/soc/soc_connect/reset_entry.S',
             'PROGRAM_SOURCES=verif/soc/soc_connect/boot.c'], OUT / 'boot_build.log')
    command(['make', '-C', 'sw', 'PROGRAM=soc_connect', 'MEMORY=sram',
             'ARCH=rv32im_zicsr_zifencei',
             'PROGRAM_SOURCES=verif/soc/soc_connect/main.c sw/bsp/cache.c sw/drivers/plic.c',
             'CFLAGS_EXTRA=-I' + str(ROOT / 'sw/drivers/include')], OUT / 'sw_build.log')
    pack_image(ROOT / 'build/sw/soc_connect_boot/rom.hex', OUT / 'rom.hex')
    pack_image(ROOT / 'build/sw/soc_connect/sram.hex', OUT / 'sram.hex')
    sources = expand_files(HERE / 'files.f')
    command(['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
             '--top-module', 'edrv32_soc_top'] + expand_files(ROOT / 'rtl/filelists/soc.f'),
            OUT / 'lint.log')
    command(['verilator', '--binary', '--timing', '--top-module', 'edrv32_soc_connect_tb',
             '-j', '1', '+define+SIM_MODE', '--output-split', '10000',
             '--output-split-cfuncs', '100', '-CFLAGS', '-O0',
             '--Mdir', str(OUT / 'obj'), '-o', 'sim'] + sources, OUT / 'compile.log')
    started = time.monotonic()
    command([str(OUT / 'obj/sim'),
             '+ROM_HEX=' + str(OUT / 'rom.hex'),
             '+SRAM_HEX=' + str(OUT / 'sram.hex')], OUT / 'run.log')
    print((OUT / 'run.log').read_text(), end='')
    print(f'soc_connect simulation elapsed={time.monotonic() - started:.3f}s')


if __name__ == '__main__':
    main()
