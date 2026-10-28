#!/usr/bin/env python3
# File: run_spike.py
# Spec: sys-subsys-plan S-W1
# Description: Run the software-only driver/handoff checks with generated RAM mappings.
# Clock domain: none (host tool).
"""Run sys_spike. Source the EdRV32 environment and build it with sw/Makefile first."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[3]
constants = {
    name: int(value, 16)
    for name, value in re.findall(
        r'^#define (EDRV32_\w+) (0x[0-9a-fA-F]+)u$',
        (root / 'sw/bsp/include/soc_map.h').read_text(), re.MULTILINE)
}
regions = ('SRAM', 'CLINT', 'PLIC', 'SYS_APB')
memory = ','.join(
    f'{constants["EDRV32_" + name + "_BASE"]:#x}:'
    f'{constants["EDRV32_" + name + "_SIZE"]:#x}' for name in regions)
for program in ('sys_spike', 'sc01', 'sc04'):
    command = [
        'spike', '--isa=rv32im_zicsr_zifencei', '--disable-dtb',
        f'--pc={constants["EDRV32_SRAM_BASE"]:#x}', '-m' + memory,
        str(root / f'build/sw/{program}/{program}.elf'),
    ]
    subprocess.run(command, check=True, timeout=30)
    print(f'PASS {program}: reached tohost', flush=True)
