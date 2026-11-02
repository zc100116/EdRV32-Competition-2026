#!/usr/bin/env python3
# File: run.py
# Design: showcase 4.1--4.4; CLAUDE 9.2 backdoor software test.
# Description: Run actual showcase ELF on the B3R board with sparse DDR preload.
# Clock domain: host tool; unmodified board system/video clocks.
from pathlib import Path
import struct
import subprocess
import sys
import time
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402
from tools.elf2mem import convert  # noqa: E402
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/board_showcase'


def command(args, name):
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / name).open('w') as log:
        subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)


def main():
    command(['make', '-C', 'sw', 'PROGRAM=showcase'], 'software.log')
    games = OUT / 'games'
    games.mkdir(parents=True, exist_ok=True)
    (games / 'test.nes').write_bytes(
        (ROOT / 'sw/apps/nes/roms/nrom-template.nes').read_bytes())
    (games / 'games.txt').write_text('测试游戏|test.nes|\n')
    elf = OUT / 'showcase-games.elf'
    command(['python3', 'tools/sw/pack_games.py',
             'build/sw/showcase/showcase.elf', str(games), str(elf)], 'pack.log')
    convert(elf, OUT / 'image')
    blob = elf.read_bytes()
    symbols = subprocess.check_output(['riscv-none-elf-nm', '-S', str(elf)], text=True)
    surface = next(line.split() for line in symbols.splitlines()
                   if line.split()[-1] == 'surfaces')
    surface_base = int(surface[0], 16) - 0x80000000
    surface_bytes = int(surface[1], 16)
    entry = struct.unpack_from('<I', blob, 24)[0]
    # Two real RV32 instructions at ROM reset: LUI t0, entry; JALR zero,t0,lo.
    upper = (entry + 0x800) >> 12
    lower = entry & 0xfff
    jump = (upper << 12) | (5 << 7) | 0x37
    jalr = (lower << 20) | (5 << 15) | 0x67
    rom = OUT / 'rom64.hex'
    rom.write_text(f'{(jalr << 32) | jump:016x}\n')
    sources = expand_files(HERE / 'files.f')
    common = ['--timing', '-Wall', '+define+SIM_MODE',
              '--top-module', 'edrv32_board_showcase_tb'] + sources
    command(['verilator', '--lint-only'] + common, 'lint.log')
    obj = OUT / 'obj'
    command(['verilator', '--binary', '-j', '1', '-CFLAGS', '-O1', '--Mdir', str(obj),
             '-o', 'sim'] + common, 'compile.log')
    start = time.monotonic()
    command([str(obj / 'sim'), '+ROM_HEX=' + str(rom),
             '+DDR_HEX=' + str(OUT / 'image/ddr.hex'),
             f'+NES_BASE={surface_base:08x}', f'+NES_BYTES={surface_bytes:08x}'],
            'simulation.log')
    if 'PASS board_showcase' not in (OUT / 'simulation.log').read_text():
        raise RuntimeError('board_showcase missing PASS')
    print(f'PASS board_showcase simulation={time.monotonic() - start:.2f}s')


if __name__ == '__main__':
    main()
