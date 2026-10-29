#!/usr/bin/env python3
# File: run.py
# Spec: Task B3-10; CLAUDE.md 9.2.
# Description: Build actual BIOS and SRAM test images, lint, and run the board test.
# Clock domain: none (host tool).
"""Run the vision plus NPU board connectivity simulation."""
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.fpga.mem_init import pack_image  # noqa: E402
from tools.regress import expand_files  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/board_vnpu'


def command(args, log):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as output:
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def main():
    command(['make', '-C', 'sw', 'PROGRAM=bootloader'], OUT / 'bootloader.log')
    command(['make', '-C', 'sw', 'PROGRAM=board_vnpu'], OUT / 'software.log')
    rom = OUT / 'rom64.hex'
    sram = OUT / 'sram64.hex'
    pack_image(ROOT / 'build/sw/bootloader/rom.hex', 2048, rom)
    pack_image(ROOT / 'build/sw/board_vnpu/sram.hex', 8192, sram)
    sources = expand_files(HERE / 'files.f')
    common = ['--timing', '-Wall', '+define+SIM_MODE',
              '--top-module', 'edrv32_board_vnpu_tb'] + sources
    command(['verilator', '--lint-only'] + common, OUT / 'lint.log')
    obj = OUT / 'obj'
    command(['verilator', '--binary', '-j', '1', '-CFLAGS', '-O1', '--Mdir', str(obj), '-o', 'sim'] + common,
            OUT / 'compile.log')
    start = time.monotonic()
    log = OUT / 'simulation.log'
    command([str(obj / 'sim'), '+ROM_HEX=' + str(rom), '+SRAM_HEX=' + str(sram)], log)
    elapsed = time.monotonic() - start
    if 'PASS board_vnpu BIOS, IDs, RND empty slot, PLIC10 DONE, DDR 64x4 readback' not in log.read_text():
        raise RuntimeError(f'{log}: missing PASS')
    print(f'PASS board_vnpu simulation={elapsed:.2f}s: {log}', flush=True)


if __name__ == '__main__':
    main()
