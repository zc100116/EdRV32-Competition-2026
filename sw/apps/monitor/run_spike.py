#!/usr/bin/env python3
# File: run_spike.py
# Spec: edrv32-soc-spec 7.5; S-W2 software-only acceptance.
# Description: Build and run the monitor computation/formatting check via existing Spike settings.
# Clock domain: none (host tool).
"""Run after sourcing ~/.local/opt/edrv32/env.sh; logs stay under build/sw/monitor-spike."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[3]
output = root / 'build/sw/monitor-spike'
output.mkdir(parents=True, exist_ok=True)
with (output / 'build.log').open('w') as log:
    subprocess.run(['make', '-C', str(root / 'sw'), 'PROGRAM=monitor', 'MEMORY=sram',
                    'MONITOR_SPIKE=1', f'OUT={output}'],
                   cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
constants = {
    name: int(value, 16)
    for name, value in re.findall(
        r'^#define (EDRV32_\w+) (0x[0-9a-fA-F]+)u$',
        (root / 'sw/bsp/include/soc_map.h').read_text(), re.MULTILINE)
}
memory = ','.join(
    f'{constants["EDRV32_" + name + "_BASE"]:#x}:'
    f'{constants["EDRV32_" + name + "_SIZE"]:#x}' for name in ('ROM', 'SRAM'))
command = ['spike', '--isa=rv32imc_zicsr_zifencei_zicntr_zihpm', '--priv=m',
           '--pmpregions=0', '--no-dm', '--disable-dtb', '-m' + memory,
           f'--pc={constants["EDRV32_SRAM_BASE"]:#x}', str(output / 'monitor.elf')]
with (output / 'console.log').open('w') as log:
    subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
                   check=True, timeout=60)
print((output / 'console.log').read_text(), end='')
print(f'PASS monitor Spike: {output / "console.log"}')
