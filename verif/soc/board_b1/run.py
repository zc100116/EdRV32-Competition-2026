#!/usr/bin/env python3
# File: run.py
# Spec: board-plan B1-4/B1-5; CLAUDE.md 9.2.
# Description: Build boot/monitor and a small UART payload, then check the board top.
#              Share PDS/simulation word packing and exercise uart_tool's emitted stream.
# Clock domain: none (host tool).
"""Run preload/menu and front-door UART download board simulations serially."""
import argparse
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.fpga.mem_init import pack_image  # noqa: E402
from tools.regress import expand_files  # noqa: E402
from verif.block.sys_cpu.uart_checks import (  # noqa: E402
    check_boot, check_system_info, check_build_fields, MENU)

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/board_b1'


def command(args, log):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as output:
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', choices=('menu', 'download', 'window'))
    case = {'menu': 0, 'download': 1, 'window': 2}[parser.parse_args().case]
    commit = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'],
                                     cwd=ROOT, text=True).strip()
    compiler = 'GCC ' + subprocess.check_output(
        ['riscv-none-elf-gcc', '-dumpfullversion'], text=True).strip()
    command(['make', '-C', 'sw', 'PROGRAM=bootloader'], OUT / 'bootloader.log')
    rom = OUT / 'rom64.hex'
    sram = OUT / 'sram64.hex'
    wire = OUT / 'download.wire'
    pack_image(ROOT / 'build/sw/bootloader/rom.hex', 2048, rom)
    if case == 0:
        command(['make', '-C', 'sw', 'PROGRAM=monitor'], OUT / 'monitor.log')
        pack_image(ROOT / 'build/sw/monitor/sram.hex', 8192, sram)
    elif case == 1:
        payload = OUT / 'download'
        command(['make', '-C', 'sw', 'PROGRAM=sc04', 'OUT=' + str(payload),
                 'PROGRAM_SOURCES=verif/soc/board_b1/download.c sw/drivers/uart.c '
                 'sw/bsp/cache.c'],
                OUT / 'download_build.log')
        command(['python3', 'tools/board/uart_tool.py', str(payload / 'sc04.bin'),
                 '--emit', str(wire)], OUT / 'emit.log')
    obj = OUT / 'obj'
    command(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
             '-CFLAGS', '-O3 -flto=1', '-LDFLAGS', '-flto=1',
             '+define+SIM_MODE', '--top-module', 'edrv32_board_b1_tb',
             '--Mdir', str(obj), '-o', 'sim'] + expand_files(HERE / 'files.f'),
            OUT / 'compile.log')
    log = OUT / f'case{case}.log'
    args = [str(obj / 'sim'), f'+CASE_ID={case}', '+ROM_HEX=' + str(rom)]
    if case == 0:
        args += ['+SRAM_HEX=' + str(sram)]
    elif case == 1:
        args += ['+DOWNLOAD_WIRE=' + str(wire)]
    start = time.monotonic()
    command(args, log)
    elapsed = time.monotonic() - start
    text = log.read_text()
    if f'PASS board_b1 case={case}' not in text:
        raise RuntimeError(f'{log}: missing PASS')
    if case == 0:
        check_boot(text.split('Boot SRAM\n')[0], commit, compiler)
        info = text.split(MENU + '\n')[1]
        check_system_info(info, commit, compiler)
        check_build_fields(info, compiler)
    print(f'PASS board_b1 case={case} simulation={elapsed:.1f}s: {log}', flush=True)


if __name__ == '__main__':
    main()
