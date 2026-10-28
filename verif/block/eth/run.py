#!/usr/bin/env python3
# File: run.py
# Spec: eth-testplan 4, 6; CLAUDE.md 9.1.
# Description: Generates independent vectors, compiles once and runs cases serially.
# Clock domain: none (host runner).
import argparse
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
BASE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files  # noqa: E402
from cases import generate  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tier', choices=['smoke', 'random', 'perf'])
    args = parser.parse_args()
    out = ROOT / 'build/eth' / args.tier
    out.mkdir(parents=True, exist_ok=True)
    cases = generate(args.tier, out)
    subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                    '+define+SIM_MODE', '--top-module', 'edrv32_eth_tb',
                    '--Mdir', str(out / 'obj'), '-o', 'sim',
                    *expand_files(BASE / 'files.f')], cwd=ROOT, check=True)
    for name, directory in cases:
        print(f'RUN {name}', flush=True)
        subprocess.run([str(out / 'obj/sim'), f'+SCRIPT={directory / "script.txt"}',
                        f'+VECTORS={directory}'], cwd=ROOT, check=True)
    print(f'PASS ETH {args.tier}: {len(cases)} cases')


if __name__ == '__main__':
    main()
