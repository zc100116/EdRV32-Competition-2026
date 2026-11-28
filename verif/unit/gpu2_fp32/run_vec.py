#!/usr/bin/env python3
"""VT04 native four-lane operations, staged cancellation, independent response queues."""
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu2 import fp32 as f
from tools.regress import expand_files

out = ROOT / 'build/gpu2_fp32'
out.mkdir(parents=True, exist_ok=True)
rng = random.Random(20261128)
count = 100000 if '--full' in sys.argv else 2048

def flat(words):
    return ''.join(f'{w:08x}' for w in reversed(words))

with (out / 'vec.txt').open('w') as stream:
    stream.write(f'{count}\n')
    for idx in range(count):
        op = idx % 4
        a, b, c = [[rng.getrandbits(32) for _ in range(4)] for _ in range(3)]
        if idx == 2:
            a = [0x3f800001, 0x3f800000, 0, 0x7fc00000]
            b = [0x3f7ffffe, 0xbf800000, 0, 0x7f800000]
        result = [f.fma(a[i], b[i], c[i]) if op == 1 else f.mul(a[i], b[i])
                  for i in range(4)]
        dot = f.dot(a, b, 3 if op == 2 else 4)
        stream.write(f'{op:x} {flat(a)} {flat(b)} {flat(c)} {flat(result)} {dot:08x}\n')
subprocess.run(['verilator', '--binary', '--timing', '--timescale', '1ns/1ps',
                '-j', '1', '--top-module', 'tb_vec', '--Mdir', str(out / 'obj_vec'),
                '-o', 'sim', *expand_files(ROOT / 'verif/unit/gpu2_fp32/vec.f')],
               cwd=ROOT, check=True)
subprocess.run([str(out / 'obj_vec/sim'), '+VECTORS=' + str(out / 'vec.txt')],
               cwd=ROOT, check=True)
