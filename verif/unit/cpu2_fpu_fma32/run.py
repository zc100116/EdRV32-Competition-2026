#!/usr/bin/env python3
"""Run exact S unit vectors in F and FD tag configurations."""
import argparse
from pathlib import Path
import subprocess
import sys
from unit_vectors import generate

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', choices=('smoke', 'full'))
    parser.add_argument('--unit', choices=('fma32', 'short', 'convert'), default='fma32')
    parser.add_argument('--softfloat-root', type=Path)
    args = parser.parse_args()
    out = ROOT / ('build/cpu2_fpu_' + args.unit)
    out.mkdir(parents=True, exist_ok=True)
    vectors = out / (args.tier + '.txt')
    if args.softfloat_root is None:
        generate(vectors, args.unit, args.tier)
    sys.path.insert(0, str(ROOT / 'tools'))
    from regress import expand_files
    sources = expand_files(ROOT / f'verif/unit/cpu2_fpu_{args.unit}/files.f')
    if args.unit == 'fma32' and args.tier == 'full':
        apm_obj = out / 'apm_obj'
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '--top-module', 'apm_tb',
                        '-DSIM_MODE', *sources, '--Mdir', str(apm_obj), '-o', 'sim', '-j', '1'],
                       cwd=ROOT, check=True)
        subprocess.run([str(apm_obj/'sim')], cwd=ROOT, check=True)
    for issue_width, fmt in ((1, 'F'), (1, 'FD'), (2, 'F'), (2, 'FD')):
        obj = out / (f'obj_w{issue_width}_' + fmt)
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '--top-module', 'tb',
                        '-DSIM_MODE', f'-GISSUE_WIDTH={issue_width}', '-GFPU_FORMAT="' + fmt + '"', *sources,
                        '--Mdir', str(obj), '-o', 'sim', '-j', '1'], cwd=ROOT, check=True)
        plusargs = []
        selected = vectors
        if args.softfloat_root is not None:
            operations = {
                'fma32': ('add','sub','mul','madd','msub','nmadd','nmsub'),
                'short': ('sgnj','sgnjn','sgnjx','min','max','eq','lt','le','class'),
                'convert': ('to_w','to_wu','from_w','from_wu','mv_x_w','mv_w_x'),
            }[args.unit]
            selected = out / ('softfloat-' + fmt + '.vec')
            source = args.softfloat_root / ('smoke-' + fmt.lower())
            with selected.open('w') as stream:
                for op in operations:
                    paths = sorted(source.glob(op + '_32_rm*.vec'))
                    if not paths:
                        raise FileNotFoundError(f'Missing {source}/{op}_32_rm*.vec')
                    for path in paths:
                        stream.write(path.read_text())
            plusargs.append('+SOFTFLOAT')
        for protocol in ([], ['+STRESS']):
            subprocess.run([str(obj/'sim'), '+VECTORS=' + str(selected), *plusargs, *protocol],
                           cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
