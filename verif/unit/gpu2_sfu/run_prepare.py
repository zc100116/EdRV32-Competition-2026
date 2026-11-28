#!/usr/bin/env python3
"""Check three front-end stages against original M5/M6 request inputs."""
from pathlib import Path
import math
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu2 import fp32 as f
from tools.gpu2.corpus import capture
from tools.regress import expand_files

out = ROOT / 'build/gpu2_sfu'
out.mkdir(parents=True, exist_ok=True)
rows = capture(full='--full' in sys.argv)
if '--full' not in sys.argv:
    groups = [[r for r in rows if r[0] == op][:256] for op in range(4)]
    rows = [row for group in groups for row in group]
with (out / 'prepare.txt').open('w') as stream:
    stream.write(f'{len(rows)}\n')
    for op, word, expected in rows:
        x = f.value(word)
        special = (not math.isfinite(x) or (x == 0 and op != 3)
                   or (op in (1, 2) and x < 0)
                   or (op == 3 and (x >= 128 or x <= -150)))
        index, field0, field3, scale, sign, exp_fma = 0, 0, 0, 0, 0, 0
        if not special:
            m, e = math.frexp(abs(x))
            m, e = m * 2, e - 1
            if op == 0:
                field0, index, scale, sign = f.bits(-m), int((m-1)*64), -e, word >> 31
            elif op == 1:
                if e & 1:
                    m, e = m * 2, e - 1
                field0, index, scale = f.bits(-.5*m), int((m-1)*64/3), -e//2
            elif op == 2:
                if m >= 1.5:
                    m, e = m / 2, e + 1
                index = round((m - .75)*64)
                field0, field3 = f.bits(e), f.bits(m-(.75+index/64))
            else:
                scale = math.floor(x)
                index = int((x-scale)*64)
                exp_fma = int(-1/64 < x < 0)
                field3 = word if abs(x) < 1/64 else f.bits(x-scale-index/64)
        ctrl = int(special) | (sign << 1) | (exp_fma << 2) | ((op < 2) << 3) | ((op == 3) << 4)
        stream.write(f'{op:x} {word:08x} {index:x} {field0:08x} {field3:08x} '
                     f'{scale & 1023:03x} {ctrl:02x} {expected:08x}\n')
subprocess.run(['verilator', '--binary', '--timing', '--timescale', '1ns/1ps', '-j', '1',
                '--top-module', 'tb_prepare', '--Mdir', str(out / 'obj_prepare'),
                '-o', 'sim', *expand_files(ROOT / 'verif/unit/gpu2_sfu/files.f')],
               cwd=ROOT, check=True)
subprocess.run([str(out / 'obj_prepare/sim'), '+VECTORS=' + str(out / 'prepare.txt')],
               cwd=ROOT, check=True)
