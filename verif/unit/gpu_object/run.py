#!/usr/bin/env python3
"""Build and run the self-checking gpu-spec 2.9 object unit test."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files
from verif.unit.gpu_object.vectors import generate

out = ROOT / 'build/gpu_object'
out.mkdir(parents=True, exist_ok=True)
generate(out)
subprocess.run(['verilator', '--binary', '--timing', '--timescale', '1ns/1ps', '-j', '1',
                '--top-module', 'tb_gpu_object', '--Mdir', str(out / 'obj'),
                '-o', 'sim', '+incdir+' + str(out),
                *expand_files(ROOT / 'verif/unit/gpu_object/files.f')],
               cwd=ROOT, check=True)
subprocess.run([str(out / 'obj/sim')], cwd=ROOT, check=True)
