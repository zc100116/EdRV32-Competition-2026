#!/usr/bin/env python3
"""Run the GPU palette self-check on the simulation host."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

subprocess.run([sys.executable, 'verif/unit/gpu_texture/generate.py',
                'build/gpu_texture/vectors'], cwd=ROOT, check=True)
out = ROOT / 'build/gpu_palette'
out.mkdir(parents=True, exist_ok=True)
files = expand_files(ROOT / 'verif/unit/gpu_palette/files.f')
args = []
for item in files:
    if item.startswith('+incdir+'):
        args += ['-I' + directory for directory in item[8:].split('+')]
    else:
        args.append(item)
subprocess.run(['iverilog', '-g2012', '-DSIM_MODE', '-s', 'tb_gpu_palette',
                '-o', str(out / 'sim')] + args, cwd=ROOT, check=True)
subprocess.run(['vvp', str(out / 'sim')], cwd=ROOT, check=True)
