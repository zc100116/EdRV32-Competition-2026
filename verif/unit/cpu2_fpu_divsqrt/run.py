#!/usr/bin/env python3
"""FV08 F and FD exact-reference regressions, seed 0xF03+precision."""
import argparse
from pathlib import Path
import subprocess
from vectors import generate

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', choices=('smoke', 'full'))
    args = parser.parse_args()
    out = ROOT / 'build/cpu2_fpu_divsqrt'
    out.mkdir(parents=True, exist_ok=True)
    for width in (32, 64):
        generate(out / f'{args.tier}{width}.txt', width,
                 2000 if args.tier == 'smoke' else 200000)
    here = Path(__file__).resolve().parent
    sources = [str((here / line).resolve()) for line in (here / 'files.f').read_text().splitlines()]
    for fmt in ('F', 'FD'):
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '--top-module', 'tb',
                        '-GFPU_FORMAT=' + str(int.from_bytes(fmt.encode(), 'big')),
                        *sources, '--Mdir', str(out / fmt), '-o', 'sim', '-j', '1'],
                       cwd=ROOT, check=True)
        subprocess.run([str(out / fmt / 'sim'),
                        '+S=' + str(out / f'{args.tier}32.txt'),
                        '+D=' + str(out / f'{args.tier}64.txt')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
