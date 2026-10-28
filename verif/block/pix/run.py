#!/usr/bin/env python3
# File: run.py
# Spec: PIX testplan 2-6; CLAUDE.md 9.1.
# Description: Export TB source frames, generate independent expectations, replay serially.
# Clock domain: host.
import argparse
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files  # noqa: E402
from scenarios import cases  # noqa: E402
from pix_ref import generate  # noqa: E402


def execute(command, log, timeout):
    with log.open('w') as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        print(log.read_text(), flush=True)
        raise RuntimeError(f'command failed ({result.returncode}), log: {log}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', choices=('smoke', 'full'))
    args = parser.parse_args()
    out = ROOT / 'build/pix/dut'
    out.mkdir(parents=True, exist_ok=True)
    top = 'edrv32_pix_tb'
    files = 'files.f'
    sources = expand_files(ROOT / 'verif/block/pix' / files)
    compile_command = ['verilator', '--binary', '--timing', '-j', '1', '-Wall',
                       '--timescale', '1ns/1ps', '-CFLAGS', '-O0',
                       '--top-module', top, '--Mdir', str(out / 'obj'), '-o', 'sim',
                       '+define+SIM_MODE', *sources]
    execute(compile_command, out / 'compile.log', 300)
    selected = cases(args.tier)
    for name, number, frames in selected:
        directory = out / name
        directory.mkdir(exist_ok=True)
        (directory / 'scenario.txt').write_text(
            ''.join(' '.join(map(str, frame)) + '\n' for frame in frames))
        command = [str(out / 'obj/sim'), f'+CASE={number}', f'+DIR={directory}']
        execute([*command, '+PREPARE=1'], directory / 'prepare.log', 120)
        # The TB has now written the exact RGB565 input frames; the model consumes them.
        generate(directory)
        execute(command, directory / 'run.log', 300)
        output = (directory / 'run.log').read_text()
        if 'PASS' not in output or 'FAIL' in output:
            raise RuntimeError(f'{name}: missing PASS or reported FAIL: {output}')
        print(output.strip(), flush=True)
    print(f'PASS PIX {args.tier}: {len(selected)} scenarios')


if __name__ == '__main__':
    main()
