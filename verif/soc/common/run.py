#!/usr/bin/env python3
# File: run.py
# Spec: soc-testplan 2, 6; CLAUDE.md 9.1-9.3.
# Description: Build software, prepare reference images and run the shared timed SoC bench.
#              Keep compiler, lint, simulator and UART evidence under build/.
# Clock domain: host.
from pathlib import Path
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files
from verif.soc.soc_connect.run import pack_image

COMMON = Path(__file__).resolve().parent
BUILD = ROOT / 'build/soc_full'


def command(args, log):
    with log.open('w') as output:
        output.write(shlex.join(args) + '\n')
        output.flush()
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def run(here, number):
    out = BUILD / here.name
    out.mkdir(parents=True, exist_ok=True)
    flags = ['ARCH=rv32im_zicsr_zifencei',
             'CFLAGS_EXTRA=-I' + str(ROOT / 'sw/drivers/include')]
    program = here.name
    sources = f'sw/tests/soc/{program}/main.c'
    if number != 1:
        sources += (' sw/tests/soc/common.c sw/drivers/uart.c sw/drivers/plic.c'
                    ' sw/drivers/clint.c sw/drivers/i2c.c sw/drivers/gpio.c sw/bsp/cache.c')
        if number in (8, 9):
            sources += ' sw/tests/soc/concurrent.c'
        flags[-1] += ' -I' + str(ROOT / 'sw/tests/soc')
    command(['make', '-C', 'sw', f'PROGRAM={program}', 'MEMORY=sram',
             'PROGRAM_SOURCES=' + sources] + flags, out / 'sw_build.log')
    pack_image(ROOT / f'build/sw/{program}/sram.hex', out / 'sram.hex')
    if number == 1:
        command(['make', '-C', 'sw', 'PROGRAM=bootloader'], out / 'boot_build.log')
        pack_image(ROOT / 'build/sw/bootloader/rom.hex', out / 'rom.hex')
        command(['riscv-none-elf-objcopy', '-O', 'binary',
                 str(ROOT / f'build/sw/{program}/{program}.elf'),
                 str(out / 'download.bin')], out / 'objcopy.log')
    else:
        command(['make', '-C', 'sw', 'PROGRAM=soc_test_boot', 'MEMORY=rom',
                 'PROGRAM_BSP=sw/tests/soc/reset_entry.S',
                 'PROGRAM_SOURCES=sw/tests/soc/boot.c'], out / 'boot_build.log')
        pack_image(ROOT / 'build/sw/soc_test_boot/rom.hex', out / 'rom.hex')
    command(['python3', str(COMMON / 'check_style.py')], out / 'style.log')
    files = expand_files(here / 'files.f')
    command(['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
             '--top-module', 'edrv32_soc_tb'] + files, out / 'lint.log')
    command(['verilator', '--binary', '--timing', '--top-module', 'edrv32_soc_tb',
             '-j', '1', '+define+SIM_MODE', '--output-split', '10000',
             '--output-split-cfuncs', '100', '-CFLAGS', '-O2',
             '--Mdir', str(BUILD / 'obj'), '-o', 'sim'] + files, out / 'compile.log')
    if number != 1:
        command([str(Path.home() / '.local/opt/edrv32-py/bin/python'),
                 str(COMMON / 'prepare.py'), str(out), str(number)], out / 'reference.log')
    started = time.monotonic()
    plusargs = ['+DDR_HEX=' + str(out / 'ddr.hex')] if (out / 'ddr.hex').exists() else []
    command([str(BUILD / 'obj/sim'), f'+CASE={number}', '+DATA_DIR=' + str(out),
             '+ROM_HEX=' + str(out / 'rom.hex'),
             '+SRAM_HEX=' + str(out / 'sram.hex')] + plusargs, out / 'run.log')
    print((out / 'run.log').read_text(), end='')
    print(f'SC-{number:02d} simulation elapsed={time.monotonic() - started:.3f}s')
