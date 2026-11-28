#!/usr/bin/env python3
"""Build and run one G-P03/G-P04 probe through the repository regression entry."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files


def main():
    name = sys.argv[1]
    output = ROOT / 'build/gpu2' / name
    output.mkdir(parents=True, exist_ok=True)
    if name == 'setup':
        from setup_reference import vectors
        vectors(output / 'vectors.txt')
    else:
        from banks_reference import trace
        trace(output / 'trace.txt')
    subprocess.run(['verilator', '--binary', '--timing', '-j', '1', '--top-module', 'tb',
                    '--Mdir', str(output / 'obj'), '-o', 'sim', '+define+SIM_MODE',
                    *expand_files(ROOT / f'verif/unit/gpu2_{name}/files.f')], check=True,
                   cwd=ROOT)
    subprocess.run([str(output / 'obj/sim')], check=True, cwd=ROOT)


if __name__ == '__main__':
    main()
