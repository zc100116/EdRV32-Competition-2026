#!/usr/bin/env python3
# File: build_cpu2_tests.py; Spec: cpu-v2-testplan CV01/CV06/CV15; Clock: host.
"""Build CPU v2 NONE smoke programs with GCC 15.2 and Zba enabled."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ENV = ROOT / 'verif/block/cpu2_core/env'
OUT = ROOT / 'build/cpu2_core/programs'
ISA = 'rv32im_zicsr_zifencei_zba'


def build(source, name):
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    elf = out / (name + '.elf')
    cmd = ['riscv-none-elf-gcc', '-march=' + ISA, '-mabi=ilp32', '-mcmodel=medany',
           '-nostdlib', '-nostartfiles', '-static', '-Wl,--no-relax',
           '-T' + str(ENV / 'link.ld'), '-DTEST_ENTRY=_start', '-I' + str(ENV),
           '-I' + str(ROOT / 'third_party/riscv-tests/env'),
           '-I' + str(ROOT / 'third_party/riscv-tests/isa/macros/scalar'),
           str(ENV / 'boot.S'), str(source), '-o', str(elf)]
    subprocess.run(cmd, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/elf2mem.py'), str(elf), str(out)],
                   check=True, stdout=subprocess.DEVNULL)
    image = []
    for region, base in [('rom', 0), ('sram', 0x10000000), ('ddr', 0x80000000)]:
        for line in (out / (region + '.hex')).read_text().splitlines():
            image.append(f'@{int(line[1:], 16) + base:08x}' if line.startswith('@') else line)
    (out / 'mem.hex').write_text('\n'.join(image) + '\n')
    symbols = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    tohost = next(int(line.split()[0], 16) for line in symbols.splitlines()
                  if line.split()[-1] == 'tohost')
    return {'name': name, 'image': str(out.relative_to(ROOT) / 'mem.hex'),
            'elf': str(elf.relative_to(ROOT)), 'tohost': f'{tohost:08x}'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['minimal', 'isa', 'coremark'], default='isa')
    args = parser.parse_args()
    version = subprocess.check_output(['riscv-none-elf-gcc', '-dumpfullversion'], text=True).strip()
    if args.suite == 'coremark':
        out = OUT / 'coremark'
        flags = (f'-march={ISA} -mabi=ilp32 -std=c11 -Wall -Wextra -Werror '
                 '-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 '
                 '-falign-jumps=4 -falign-loops=4 -ffreestanding -fno-builtin '
                 '-ffunction-sections -fdata-sections '
                 f'-I{ROOT}/sw/bsp/include -I{ROOT}/sw/apps/coremark '
                 f'-I{ROOT}/third_party/coremark -DITERATIONS=10')
        command = ['make', '-j', '1', '-C', str(ROOT / 'sw'), 'PROGRAM=coremark',
                   'MEMORY=sram', f'OUT={out}', f'ARCH={ISA}', 'CFLAGS=' + flags,
                   'BSP=sw/bsp/start.S verif/block/cpu2_core/env/coremark_host.c',
                   'LDFLAGS=-nostdlib -Wl,--gc-sections -Wl,-T,sw/bsp/ld/sram.ld '
                   '-Wl,--defsym,cpu2_console=0x40007000']
        subprocess.run(command, cwd=ROOT, check=True)
        elf = out / 'coremark.elf'
        entry = struct.unpack_from('<I', elf.read_bytes(), 24)[0]
        boot = struct.pack('<II', (((entry + 0x800) >> 12) << 12) | 0x2b7,
                           ((entry & 0xfff) << 20) | 0x28067)
        image = ['@00000000'] + [f'{byte:02x}' for byte in boot]
        for region, base in [('sram', 0x10000000), ('ddr', 0x80000000)]:
            for line in (out / (region + '.hex')).read_text().splitlines():
                image.append(f'@{int(line[1:], 16) + base:08x}' if line.startswith('@') else line)
        (out / 'mem.hex').write_text('\n'.join(image) + '\n')
        symbols = {}
        for line in subprocess.check_output(['riscv-none-elf-nm', str(elf)],
                                            text=True).splitlines():
            fields = line.split()
            if len(fields) == 3:
                symbols[fields[2]] = fields[0]
        manifest = [{'name': 'coremark', 'image': str(out.relative_to(ROOT) / 'mem.hex'),
                     'tohost': symbols['tohost'], 'begin': symbols['start_time'],
                     'end': symbols['stop_time'], 'iterations': 10}]
        (OUT / 'coremark.json').write_text(json.dumps(manifest, indent=2) + '\n')
        return
    sources = [(ENV / 'smoke.S', 'smoke'), (ENV / 'trap.S', 'trap'),
               (ENV / 'redirect.S', 'redirect'), (ENV / 'dispatch.S', 'dispatch'),
               (ENV / 'load_stream.S', 'load_stream')]
    if args.suite == 'isa':
        for group in ['rv32ui', 'rv32um']:
            for source in sorted((ROOT / 'third_party/riscv-tests/isa' / group).glob('*.S')):
                # Natural alignment is required by CPU2.1; ma_data expects emulation.
                if source.stem != 'ma_data':
                    sources.append((source, group + '-' + source.stem))
        sources.append((ROOT / 'verif/block/cpu2_core/env/zba.S', 'zba'))
    manifest = [build(source, name) for source, name in sources]
    (OUT / 'programs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'PASS built {len(manifest)} programs GCC={version} ISA={ISA}')


if __name__ == '__main__':
    main()
