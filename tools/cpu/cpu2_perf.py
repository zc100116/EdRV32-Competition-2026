#!/usr/bin/env python3
# File: cpu2_perf.py; Spec: cpu-v2-testplan CV15; Clock: host.
"""Measure an existing ELF using its start_time/stop_time retirement window."""
import argparse
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--elf', type=Path, required=True)
    parser.add_argument('--width', type=int, choices=[1, 2], required=True)
    parser.add_argument('--no-build', action='store_true')
    args = parser.parse_args()
    image = ROOT / 'build/cpu2_perf' / f'w{args.width}-image'
    image.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/elf2mem.py'), str(args.elf), str(image)],
                   check=True, stdout=subprocess.DEVNULL)
    entry = struct.unpack_from('<I', args.elf.read_bytes(), 24)[0]
    boot = struct.pack('<II', (((entry + 0x800) >> 12) << 12) | 0x2b7,
                       ((entry & 0xfff) << 20) | 0x28067)
    memory = []
    for region, base in [('rom', 0), ('sram', 0x10000000), ('ddr', 0x80000000)]:
        for line in (image / (region + '.hex')).read_text().splitlines():
            memory.append(f'@{int(line[1:], 16)+base:08x}' if line.startswith('@') else line)
    if entry != 0:
        memory += ['@00000000'] + [f'{byte:02x}' for byte in boot]
    (image / 'mem.hex').write_text('\n'.join(memory)+'\n')
    symbols = {}
    for line in subprocess.check_output(['riscv-none-elf-nm', str(args.elf)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = fields[0]
    out = ROOT / 'build/cpu2_core' / f'w{args.width}'
    out.mkdir(parents=True, exist_ok=True)
    if not args.no_build:
        command = ['verilator', '--binary', '--timing', '-Wall', '-DSIM_MODE', '-j', '4',
                   '--top-module', 'tb', f'-GISSUE_WIDTH={args.width}', '-f', 'files.f',
                   '--Mdir', str(out)]
        with (out / 'compile.log').open('w') as log:
            subprocess.run(command, cwd=ROOT / 'verif/block/cpu2_core', stdout=log,
                           stderr=subprocess.STDOUT, check=True)
    command = [str(out / 'Vtb'), '+MEM_HEX='+str(image / 'mem.hex'),
               '+TOHOST_ADDR='+symbols['tohost'], '+PERF_BEGIN='+symbols['start_time'],
               '+PERF_END='+symbols['stop_time'], '+PERF_ONLY', '+MAX_CYCLES=20000000']
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    (ROOT / 'build/cpu2_perf' / f'w{args.width}.log').write_text(result.stdout)
    print(result.stdout, end='')
    if result.returncode:
        raise RuntimeError('performance simulation failed')


if __name__ == '__main__':
    main()
