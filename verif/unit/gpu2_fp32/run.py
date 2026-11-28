#!/usr/bin/env python3
"""VT04 GPU v2 FP32 independent integer vectors and RTL scoreboard."""
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
count = 200000 if '--full' in sys.argv else 10000
edges = [0, 0x80000000, 1, 3, 0x7fffff, 0x800000, 0x3f800000,
         0x3f800001, 0x3f7ffffe, 0xbf800000, 0x7f7fffff, 0x7f800000,
         0xff800000, 0x7fc00000]
rows = [(0, 0x3f800001, 0x3f7ffffe, 0xbf800000)]
for idx in range(count):
    args = [rng.choice(edges) if idx < 1000 else rng.getrandbits(32) for _ in range(3)]
    rows.append((idx & 1, *args))
with (out / 'vectors.txt').open('w') as stream:
    stream.write(f'{len(rows)}\n')
    for mul, a, b, c in rows:
        expected = f.mul(a, b) if mul else f.fma(a, b, c)
        stream.write(f'{mul:x} {a:08x} {b:08x} {c:08x} {expected:08x} {f.mul(a, b):08x} {f.add(a, b):08x}\n')
subprocess.run(['verilator', '--binary', '--timing', '--timescale', '1ns/1ps',
                '-j', '1', '--top-module', 'tb', '--Mdir', str(out / 'obj'), '-o', 'sim',
                *expand_files(ROOT / 'verif/unit/gpu2_fp32/files.f')], cwd=ROOT, check=True)
subprocess.run([str(out / 'obj/sim'), '+VECTORS=' + str(out / 'vectors.txt')],
               cwd=ROOT, check=True)
