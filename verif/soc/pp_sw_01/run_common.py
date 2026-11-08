#!/usr/bin/env python3
# run_common.py — npu-testplan 3.10 PP-SW-01/02; CLAUDE.md 9.2.
# Build the real CPU program, BSP cache operations and independent NPU input oracle.
# Clock domain: host. Caller holds /tmp/edrv32-sim.lock for the whole simulation.
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files
from verif.soc.soc_connect.run import pack_image


def run(here):
    out = ROOT / 'build/npu/post_sw' / here.name
    out.mkdir(parents=True, exist_ok=True)

    def command(args, name):
        with (out / name).open('w') as log:
            subprocess.run(args, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)

    command(['make', '-C', 'sw', f'PROGRAM={here.name}', '-j', '1'], 'sw.log')
    command(['make', '-C', 'sw', 'PROGRAM=soc_test_boot', 'MEMORY=rom', '-j', '1',
             'PROGRAM_BSP=sw/tests/soc/reset_entry.S',
             'PROGRAM_SOURCES=sw/tests/soc/boot.c'], 'boot.log')
    pack_image(ROOT / f'build/sw/{here.name}/sram.hex', out / 'sram.hex')
    pack_image(ROOT / 'build/sw/soc_test_boot/rom.hex', out / 'rom.hex')
    sources = expand_files(here / 'files.f')
    flags = ['--timing', '-Wall', '+define+SIM_MODE', '--top-module', 'edrv32_npu_post_tb']
    command(['verilator', '--lint-only', '-j', '1', *flags, *sources], 'lint.log')
    command(['verilator', '--binary', '-j', '1', *flags, '--Mdir', str(out / 'obj'),
             '-o', 'sim', *sources], 'compile.log')
    command([str(out / 'obj/sim'), '+ROM_HEX=' + str(out / 'rom.hex'),
             '+SRAM_HEX=' + str(out / 'sram.hex'),
             '+DDR_HEX=' + str(ROOT / 'build/npu/post_sw/data/ddr.hex')], 'run.log')
    print((out / 'run.log').read_text(), end='')
