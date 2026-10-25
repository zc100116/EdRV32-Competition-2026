#!/usr/bin/env python3
# File: build_tests.py; cpu-testplan 2.4; cpu-plan C-V1; clock: host.
# Build upstream tests for B1, emit memory images, run Spike and arch signatures.
"""Build and run the riscv-tests and architectural signature suites."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

from run_spike import ISA, run

ROOT = Path(__file__).resolve().parents[2]
ENV = ROOT / 'verif/block/cpu/env'
OUT = ROOT / 'build/cpu'
TESTS = ROOT / 'third_party/riscv-tests'
ARCH = ROOT / 'third_party/riscv-arch-test/riscv-test-suite'


def build(source, name, arch=False, compressed=True):
    out = OUT / ('arch-test' if arch else 'riscv-tests') / name
    if not compressed:
        out /= 'no-c'
    out.mkdir(parents=True, exist_ok=True)
    elf = out / (name + '.elf')
    includes = [ENV, ARCH / 'env'] if arch else [
        ENV, TESTS / 'env', TESTS / 'isa/macros/scalar']
    isa = ISA if compressed else ISA.replace('imc_', 'im_')
    if arch and not compressed:
        # The upstream macros enable RVC temporarily to fill alignment gaps.
        # Build-local macro copies keep I/M-only programs entirely 32-bit.
        adaptation = out / 'env-no-c'
        adaptation.mkdir(exist_ok=True)
        for header in ('arch_test.h', 'test_macros.h'):
            text = (ARCH / 'env' / header).read_text()
            text = text.replace('.option rvc', '.option norvc').replace('c.nop', 'nop')
            (adaptation / header).write_text(text)
        includes.insert(0, adaptation)
    args = ['riscv-none-elf-gcc', '-march=' + isa, '-mabi=ilp32', '-mcmodel=medany',
            '-nostdlib', '-nostartfiles', '-static', '-Wl,--no-relax',
            '-T' + str(ENV / 'link.ld')]
    args += ['-I' + str(path) for path in includes]
    args += ['-DTEST_ENTRY=' + ('rvtest_entry_point' if arch else '_start')]
    if arch:
        args += ['-DXLEN=32', '-DTEST_CASE_1=1']
        if 'rvtest_mtrap_routine=True' in source.read_text():
            args += ['-Drvtest_mtrap_routine=1']
    with (out / 'build.log').open('w') as log:
        subprocess.run(args + [str(ENV / 'boot.S'), str(source), '-o', str(elf)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/elf2mem.py'), str(elf), str(out)],
                   check=True)
    # B1's flat memory loader uses absolute addresses rather than region offsets.
    image = []
    for region, base in (('rom', 0), ('sram', 0x10000000), ('ddr', 0x80000000)):
        for line in (out / (region + '.hex')).read_text().splitlines():
            image.append(f'@{int(line[1:], 16) + base:08x}' if line.startswith('@') else line)
    (out / 'mem.hex').write_text('\n'.join(image) + '\n')
    run(elf, out, compressed=compressed, signature=arch)
    return elf


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('riscv-tests', 'arch-test', 'all'), default='all')
    args = parser.parse_args()
    count = 0
    if args.suite in ('all', 'riscv-tests'):
        for group in ('rv32ui', 'rv32um', 'rv32uc', 'rv32mi'):
            for source in sorted((TESTS / 'isa' / group).glob('*.S')):
                # cpu-spec 5 has no PMP; coordinator-approved testplan exclusion.
                if group == 'rv32mi' and source.stem in ('pmpaddr', 'breakpoint'):
                    continue
                # cpu-spec 4.7/6 requires traps, whereas ma_data requires emulation.
                if group == 'rv32ui' and source.stem == 'ma_data':
                    continue
                build(source, group + '-p-' + source.stem)
                count += 1
    if args.suite in ('all', 'arch-test'):
        for group in ('I', 'M', 'C', 'Zifencei', 'privilege'):
            for source in sorted((ARCH / 'rv32i_m' / group / 'src').glob('*.S')):
                # C directory also contains Zcb/Zbb tests outside cpu-spec 2.1.
                required = re.search(r'RVTEST_ISA\("([^"]+)"\)', source.read_text())[1]
                if not re.fullmatch(r'RV32I[MC]*(_Zicsr|_Zifencei)*', required):
                    continue
                build(source, group + '-' + source.stem, arch=True)
                count += 1
    print(f'PASS: {count} tests built and run')


if __name__ == '__main__':
    main()
