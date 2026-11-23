#!/usr/bin/env python3
# File: run.py
# Spec: gpu-soc-testplan 2, ST-08--14; CLAUDE.md 9.1-9.3.
# Description: Build software and a scenario against the common GPU SoC harness.
#              Reuse common image packing and command logging from the visual environment.
# Clock domain: host.
from pathlib import Path
import shlex
import sys
import time
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from verif.soc.common.run import command
from verif.soc.soc_connect.run import pack_image

COMMON = Path(__file__).resolve().parent


def sources(path, placeholder=False):
    """Explicit placeholder mode replaces only gpu.f; normal mode uses the real list."""
    result = []
    tokens = shlex.split(path.read_text(), comments=True)
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token == '-f':
            index += 1
            child = path.parent / tokens[index]
            if placeholder and child.name == 'gpu.f':
                result.append(str(COMMON / 'edrv32_gpu.v'))
            else:
                result.extend(sources(child, placeholder))
        elif token.startswith('+incdir+'):
            result.append('+incdir+' + '+'.join(
                str((path.parent / item).resolve()) for item in token[8:].split('+')))
        elif token.startswith('+'):
            result.append(token)
        else:
            result.append(str((path.parent / token).resolve()))
        index += 1
    return list(dict.fromkeys(result))


def run(here, number, placeholder=False, bios=False, software_sources=None, plusargs=()):
    """Each scenario owns its software, files.f, scenario module and external checks."""
    here = Path(here).resolve()
    out = ROOT / 'build/gpu_soc' / here.name
    out.mkdir(parents=True, exist_ok=True)
    program = here.name
    flags = ['SOC=gpu', 'ARCH=rv32im_zicsr_zifencei']
    extra = '-I' + str(ROOT / 'sw/drivers/include')
    if placeholder:
        extra += ' -DGPU_PARTIAL'
    flags += ['CFLAGS_EXTRA=' + extra]
    if software_sources is None:
        software_sources = f'sw/tests/{program}/main.c sw/drivers/uart.c sw/drivers/plic.c'
    command(['make', '-C', 'sw', f'PROGRAM={program}', 'MEMORY=sram',
             'PROGRAM_SOURCES=' + software_sources] + flags, out / 'sw_build.log')
    pack_image(ROOT / f'build/sw/{program}/sram.hex', out / 'sram.hex')
    if bios:
        command(['make', '-C', 'sw', 'PROGRAM=bootloader', 'SOC=gpu'],
                out / 'boot_build.log')
        boot = ROOT / 'build/sw/bootloader/rom.hex'
    else:
        command(['make', '-C', 'sw', 'PROGRAM=gpu_test_entry', 'MEMORY=rom',
                 'SOC=gpu', 'PROGRAM_BSP=verif/soc/soc_connect/reset_entry.S',
                 'PROGRAM_SOURCES=verif/soc/soc_connect/boot.c'], out / 'boot_build.log')
        boot = ROOT / 'build/sw/gpu_test_entry/rom.hex'
    pack_image(boot, out / 'rom.hex')
    rtl = sources(ROOT / 'rtl/filelists/gpu_soc.f', placeholder)
    command(['python3', 'tools/check/verilog_style.py',
             'rtl/soc/edrv32_gpu_soc_top.v', 'rtl/soc/edrv32_sys_subsys_gpu.v',
             'rtl/soc/edrv32_soc_gpu_boundary_gpu.v'], out / 'style.log')
    command(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
             '--top-module', 'edrv32_gpu_soc_top'] + rtl, out / 'lint.log')
    files = sources(here / 'files.f', placeholder)
    command(['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
             '--top-module', 'edrv32_gpu_soc_tb'] + files, out / 'tb_lint.log')
    command(['verilator', '--binary', '--timing', '--top-module', 'edrv32_gpu_soc_tb',
             '-j', '1', '+define+SIM_MODE', '--output-split', '10000',
             '--output-split-cfuncs', '100', '-CFLAGS', '-O2',
             '--Mdir', str(out / 'obj'), '-o', 'sim'] + files, out / 'compile.log')
    started = time.monotonic()
    command([str(out / 'obj/sim'), f'+CASE={number}', '+DATA_DIR=' + str(out),
             '+ROM_HEX=' + str(out / 'rom.hex'), '+SRAM_HEX=' + str(out / 'sram.hex'),
             f'+GPU_PARTIAL={int(placeholder)}'] + list(plusargs), out / 'run.log')
    print((out / 'run.log').read_text(), end='')
    print(f'ST-{number:02d} simulation elapsed={time.monotonic() - started:.3f}s')
