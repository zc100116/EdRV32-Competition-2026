#!/usr/bin/env python3
"""check_compile.py: showcase design 4.2/4.4; RV32 C11 compile and display IRQ test.
Clock domain: host test drives captured hardware events, no RTL simulation.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/sw/game-pack/compile'
OUT.mkdir(parents=True, exist_ok=True)
NES = ROOT / 'sw/apps/showcase/nes'
# The frame regression prepares exactly the same patched core as the board build.
CORE = ROOT / 'build/sw/game-pack/frames/step/core'
includes = [ROOT / p for p in ['third_party/lvgl', 'sw/apps/s3/lvgl',
            'sw/drivers/include', 'sw/bsp/include', 'sw/lib']]
includes += [CORE / 'cpu', NES / 'mappers']
includes += [ROOT / 'third_party/nofrendo/components/nofrendo' / p
             for p in ['', 'cpu', 'nes', 'sndhrdw', 'libsnss']]
common = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror']
flags = common + ['-march=rv32im', '-mabi=ilp32', '-fno-strict-aliasing',
                 '-DLV_CONF_INCLUDE_SIMPLE', '-DLV_FONT_SOURCE_HAN_SANS_SC_16_CJK=1']
flags += ['-I' + str(path) for path in includes]
with (OUT / 'compile.log').open('w') as log:
    for source in sorted(NES.glob('*.c')) + sorted((NES / 'mappers').glob('*.c')):
        subprocess.run(['riscv-none-elf-gcc', *flags, '-c', str(source),
                        '-o', str(OUT / (source.stem + '.o'))], check=True,
                       stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['gcc', *common, '-ffunction-sections', '-fdata-sections',
                    '-I' + str(NES), '-I' + str(ROOT / 'sw/drivers/include'),
                    '-I' + str(ROOT / 'sw/bsp/include'),
                    '-no-pie', '-mcmodel=large', '-Wl,-Ttext-segment=0x10000000',
                    '-Wl,--section-start=.bss=0x90000000',
                    '-include', str(ROOT / 'sw/apps/nes/tests/fake_mmio.h'),
                    str(ROOT / 'sw/tests/game_pack/display_irq.c'),
                    str(NES / 'display.c'), str(NES / 'display_command.c'),
                    str(ROOT / 'sw/drivers/rnd.c'), str(ROOT / 'sw/drivers/disp.c'),
                    str(ROOT / 'sw/drivers/engine.c'), str(ROOT / 'sw/drivers/plic.c'),
                    '-Wl,--gc-sections', '-o', str(OUT / 'display-irq')], check=True,
                   stdout=log, stderr=subprocess.STDOUT)
subprocess.run([str(OUT / 'display-irq')], check=True)
print('PASS all NES application/mapper sources: RV32 C11 -Wall -Wextra -Werror')
