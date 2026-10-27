#!/usr/bin/env python3
# File: run.py
# Spec: npu-spec 2.4, 3, 4; npu-testplan RG-02.
# Description: Exercise the empty-list boundary and the independent NB three-descriptor flow.
# Clock: host tool.
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

out = ROOT / 'build/npu_ctrl/top_empty'
out.mkdir(parents=True, exist_ok=True)
args = ['verilator', '--binary', '--timing', '-Wall', '-j', '1', '+define+SIM_MODE',
        '--top-module', 'tb_npu_top', '--Mdir', str(out), '-o', 'sim']
with (out/'compile.log').open('w') as log:
    subprocess.run(args+expand_files(ROOT/'verif/unit/npu_top/files.f'), cwd=ROOT,
                   check=True, stdout=log, stderr=subprocess.STDOUT)
subprocess.run([str(out/'sim')], cwd=ROOT, check=True)
subprocess.run(['python3', str(ROOT/'verif/block/npu/run.py'), '--test', 'RG-02'],
               cwd=ROOT, check=True)
