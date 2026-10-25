#!/usr/bin/env python3
# File: build_directed.py; Spec: cpu-testplan 3.3–3.7; Clock: host.
# Description: Build B1 directed programs and run their Spike reference/smoke variants.
"""Build CPU directed tests and run Spike; generated artifacts stay in build/."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

from run_spike import ISA

ROOT = Path(__file__).resolve().parents[2]
ENV = ROOT / 'verif/block/cpu/env'
TESTS = ROOT / 'sw/tests/cpu'


def build(source, out, smoke, compressed=True, defines=()):
    out.mkdir(parents=True, exist_ok=True)
    elf = out / (source.parent.name + '.elf')
    isa = ISA if compressed else ISA.replace('imc_', 'im_')
    args = ['riscv-none-elf-gcc', '-march=' + isa, '-mabi=ilp32', '-mcmodel=medany',
            '-Wall', '-Wextra', '-Werror', '-Wa,--fatal-warnings',
            '-nostdlib', '-nostartfiles', '-static', '-Wl,--no-relax',
            '-Wl,--fatal-warnings', '-T' + str(ENV / 'link.ld'),
            '-I' + str(TESTS / 'common'), '-DTEST_ENTRY=_start']
    args += ['-D' + define for define in defines]
    if smoke:
        args += ['-DSPIKE_SMOKE=1']
    if not compressed:
        args += ['-DRVC_DISABLED=1']
    with (out / 'build.log').open('w') as log:
        subprocess.run(args + [str(ENV / 'boot.S'), str(source), '-o', str(elf)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    with (out / 'program.dis').open('w') as log:
        subprocess.run(['riscv-none-elf-objdump', '-d', str(elf)], stdout=log, check=True)
    with (out / 'symbols.txt').open('w') as log:
        subprocess.run(['riscv-none-elf-nm', '-n', str(elf)], stdout=log, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/elf2mem.py'), str(elf), str(out)],
                   check=True)
    image = []
    for region, base in (('rom', 0), ('sram', 0x10000000), ('ddr', 0x80000000)):
        for line in (out / (region + '.hex')).read_text().splitlines():
            image.append(f'@{int(line[1:], 16) + base:08x}' if line.startswith('@') else line)
    (out / 'mem.hex').write_text('\n'.join(image) + '\n')
    return elf


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tests', nargs='*', help='test IDs, e.g. p-01 e-04; default: all')
    args = parser.parse_args()
    sources = [TESTS / name.lower() / 'main.S' for name in args.tests] if args.tests else \
        sorted(TESTS.glob('*/main.S'))
    for source in sources:
        config = json.loads((source.parent / 'b1.json').read_text())
        out = ROOT / 'build/cpu/directed' / source.parent.name
        for compressed in config['rvc']:
            variant = out if compressed else out / 'no-c'
            elf = build(source, variant / 'b1', False, compressed)
            if config['spike'] == 'smoke':
                elf = build(source, variant / 'spike', True, compressed)
            # The regression timeout terminates both the launcher and Spike.
            command = [sys.executable, str(ROOT / 'tools/cpu/run_spike.py'),
                       str(elf), str(variant / 'spike')]
            if not compressed:
                command += ['--no-c']
            with subprocess.Popen(command, start_new_session=True) as process:
                try:
                    status = process.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    raise
                if status:
                    raise subprocess.CalledProcessError(status, command)
    print(f'PASS: {len(sources)} directed tests built and run')


if __name__ == '__main__':
    main()
