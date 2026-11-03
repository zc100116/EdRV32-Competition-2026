#!/usr/bin/env python3
"""gen_fonts.py — showcase design §3: generate uncompressed Noto SC LVGL subsets."""
import argparse
from pathlib import Path
import re
import shlex
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--sizes', type=int, nargs='+', required=True)
parser.add_argument('--digit-sizes', type=int, nargs='+', default=[])
parser.add_argument('sources', type=Path, nargs='+')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
fonts = root / 'third_party/lvgl/tests/src/test_files/fonts'
builtin = root / 'third_party/lvgl/scripts/generators/built_in_font'
symbols = re.search(r'syms = "([^"]+)"', (builtin / 'built_in_font_gen.py').read_text())[1]
chars = ''.join(sorted({c for p in args.sources for c in p.read_text() if ord(c) > 127}))
args.output_dir.mkdir(parents=True, exist_ok=True)


def generate(size, digits):
    name = f'sim_digits_{size}' if digits else f'sim_font_{size}'
    output = args.output_dir / f'{name}.c'
    command = ['npx', '--yes', 'lv_font_conv@1.5.3', '--font',
               str(fonts / 'noto/NotoSansSC-Regular.ttf')]
    if digits:
        command += ['--symbols', '0123456789 FPS%']
    else:
        command += ['--range', '0x20-0x7e', '--symbols', chars, '--font',
                    str(builtin / 'FontAwesome5-Solid+Brands+Regular.woff'), '--range', symbols]
    command += ['--size', str(size), '--bpp', '4', '--no-compress', '--format', 'lvgl',
                '--lv-font-name', name, '--output', str(output)]
    subprocess.run(command, check=True)
    output.write_text('/* Command: ' + shlex.join(command) + ' */\n' + output.read_text())


for size in args.sizes:
    generate(size, False)
for size in args.digit_sizes:
    generate(size, True)
