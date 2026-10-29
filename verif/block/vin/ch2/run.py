#!/usr/bin/env python3
# File: run.py
# Spec: vin 2.8; vin-testplan VI-19 through VI-23.
# Description: Generate independent expectations, compile single-core and run CH2 cases.
# Clock domain: host.
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files
from reference import generate, selftest


def main():
    mode = sys.argv[1]
    out = ROOT / 'build/vin_ch2' / mode
    selftest()
    generate(out, mode == 'full')
    files = Path(__file__).with_name('files.f')
    flags = []
    if mode == 'selftest':
        files = files.parent / 'selftest/files.f'
        flags = ['-GHARNESS_SELFTEST=1']
    optimization = '-O1' if mode == 'full' else '-O0'
    compile_cmd = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                   '-CFLAGS', optimization, '--top-module', 'edrv32_vin_ch2_tb',
                   '--Mdir', str(out / 'obj'), '-o', 'sim', '+define+SIM_MODE',
                   *flags, *expand_files(files)]
    commands = [compile_cmd, [str(out / 'obj/sim'), f'+DIR={out}', f'+CASE={mode}']]
    for label, command in zip(('compile', 'run'), commands):
        log = out / f'{label}.log'
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream,
                                    stderr=subprocess.STDOUT, check=False)
        if result.returncode:
            print(log.read_text(), flush=True)
            raise RuntimeError(f'CH2 {mode} {label} exit={result.returncode}: {log}')
    print((out / 'run.log').read_text(), end='', flush=True)


if __name__ == '__main__':
    main()
