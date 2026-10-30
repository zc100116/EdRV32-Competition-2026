#!/usr/bin/env python3
# File: run_spike.py
# Spec: Task B3-4b; CLAUDE.md 9.2.
# Description: Serial instruction counts for O2/O3 with and without PPU rendering.
# Clock domain: none (host tool); Spike is functional and has no cycle timing model.
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
rom = root / 'sw/apps/nes/roms/nrom-template.nes'
for optimization in ('O2', 'O3'):
    for skip in (0, 1):
        output = root / f'build/sw/nes-spike-{optimization}-skip{skip}'
        output.mkdir(parents=True, exist_ok=True)
        with (output / 'build.log').open('w') as log:
            subprocess.run(['make', '-j1', '-C', str(root / 'sw'), 'PROGRAM=nes',
                            'MEMORY=ddr_app', 'NES_SPIKE=1', 'NES_DISPLAY=0', 'NES_FRAMES=180',
                            f'NES_OPT=-{optimization}', f'NES_SKIP={skip}', f'OUT={output}'],
                           cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
        # Only this generated Spike image has file bytes in the application's ROM slot.
        # The normal nes.elf retains its NOLOAD section and never embeds game data.
        spike_elf = output / 'nes-spike.elf'
        subprocess.run(['riscv-none-elf-objcopy',
                        '--set-section-flags', '.nes_rom_slot=alloc,load,contents,data',
                        '--update-section', f'.nes_rom_slot={rom}',
                        str(output / 'nes.elf'), str(spike_elf)], check=True)
        command = ['spike', '--isa=rv32im_zicsr_zifencei_zicntr_zihpm', '--priv=m',
                   '--pmpregions=0', '--no-dm', '--disable-dtb',
                   '-m0x90000000:0x04000000', '--pc=0x90000000', str(spike_elf)]
        with (output / 'console.log').open('w') as log:
            subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
                           check=True)
        print(f'{optimization} skip={skip}: {output / "console.log"}', flush=True)
        print((output / 'console.log').read_text(), end='', flush=True)
