#!/usr/bin/env python3
"""VT06 bit-exact SFU integration, real reservation assertions and concurrent setup reads."""
from pathlib import Path
import random
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu2.corpus import capture
from tools.gpu2.sfu import RCP
from tools.regress import expand_files
out = ROOT / 'build/gpu2_sfu'
out.mkdir(parents=True, exist_ok=True)
full = '--full' in sys.argv
rows = capture(full=full)
pools = [[r for r in rows if r[0] == op][:128] for op in range(4)]
rng = random.Random(20261127)
indices = [0]*4
mixed = []
for request in range(512):
    op = rng.randrange(4)
    mixed.append(pools[op][indices[op] % len(pools[op])])
    indices[op] += 1
rows = mixed + rows if full else mixed + rows[:256]
with (out / 'integrated.txt').open('w') as stream:
    stream.write(str(len(rows))+'\n')
    for op, x, expected in rows:
        stream.write(f'{op:x} {x:08x} {expected:08x}\n')
(out / 'setup.hex').write_text(''.join(f'{word:08x}\n' for word in RCP))
subprocess.run([sys.executable, '-B', 'tools/gpu2/gen_sfu_rom.py'], cwd=ROOT, check=True)
subprocess.run(['verilator', '--binary', '--timing', '--timescale', '1ns/1ps', '-j', '1',
                '--top-module', 'tb', '--Mdir', str(out / 'obj_integrated'), '-o', 'sim',
                *expand_files(ROOT / 'verif/unit/gpu2_sfu/integrated.f')], cwd=ROOT, check=True)
subprocess.run([str(out / 'obj_integrated/sim'), '+VECTORS='+str(out/'integrated.txt'),
                '+SETUP='+str(out/'setup.hex')], cwd=ROOT, check=True)
