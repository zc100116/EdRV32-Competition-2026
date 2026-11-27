#!/usr/bin/env python3
"""Build and run the smoke/full exact-reference FMA regression."""
import argparse
from pathlib import Path
import subprocess
from vectors import generate

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', choices=('smoke', 'full'))
    args = parser.parse_args()
    out = ROOT / 'build/cpu2_fpu_fma32'
    out.mkdir(parents=True, exist_ok=True)
    vectors = out / (args.tier + '.txt')
    generate(vectors, 10000 if args.tier == 'smoke' else 1000000)
    import sys
    sys.path.insert(0, str(ROOT / 'tools'))
    from regress import expand_files
    sources = expand_files(ROOT / 'verif/unit/cpu2_fpu_fma32/files.f')
    subprocess.run(['verilator', '--binary', '--timing', '-Wall', '--top-module', 'tb',
                    '-DSIM_MODE', *sources,
                    '--Mdir', str(out / 'obj'), '-o', 'sim', '-j', '1'], cwd=ROOT, check=True)
    subprocess.run([str(out / 'obj/sim'), '+VECTORS=' + str(vectors)], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
