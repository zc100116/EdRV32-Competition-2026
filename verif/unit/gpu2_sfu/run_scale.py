#!/usr/bin/env python3
"""Independent integer RNE reference for the SFU's two final scaling edges."""
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu2 import fp32 as f
from tools.regress import expand_files

out = ROOT / 'build/gpu2_sfu'
out.mkdir(parents=True, exist_ok=True)
rng = random.Random(20261128)
count = 100000 if '--full' in sys.argv else 2048
with (out / 'scale.txt').open('w') as stream:
    stream.write(str(count) + '\n')
    for idx in range(count):
        word = (rng.getrandbits(1) << 31) | (rng.randrange(1, 255) << 23) | rng.getrandbits(23)
        power = rng.randrange(-200, 201)
        sign = rng.getrandbits(1)
        special = int(idx >= 4 and idx % 32 == 0)
        special_data = (0, 0x7f800000, 0xff800000, 0x7fc00000)[(idx // 32) % 4]
        if idx < 4:
            word, sign = (idx & 1) << 31, idx >> 1
        directed = [(0x3f800000, -150), (0x3f800001, -150),
                    (0x3fc00000, -149), (0x3fa00000, -149),
                    (0x3fc00000, -148), (0x3fffffff, -127),
                    (0x3ffffffe, -127), (0x3f800000, 128),
                    (0xbf800000, -149)]
        if 4 <= idx < 4 + len(directed):
            word, power = directed[idx - 4]
            sign, special = 0, 0
        mantissa, exponent = f.finite(word)
        expected = special_data if special else f.pack(mantissa, exponent + power, word >> 31)
        if not special:
            expected ^= sign << 31
        stream.write(f'{word:08x} {power & 1023:03x} {sign:x} {special:x} '
                     f'{special_data:08x} {expected:08x}\n')
subprocess.run(['verilator', '--binary', '--timing', '--timescale', '1ns/1ps', '-j', '1',
                '--top-module', 'tb_scale', '--Mdir', str(out / 'obj_scale'), '-o', 'sim',
                *expand_files(ROOT / 'verif/unit/gpu2_sfu/scale.f')], cwd=ROOT, check=True)
subprocess.run([str(out / 'obj_scale/sim'), '+VECTORS=' + str(out / 'scale.txt')],
               cwd=ROOT, check=True)
