#!/usr/bin/env python3
# File: lint.py
# Spec: gpu-soc-testplan ST-10-ST-14; gpu_common authorized placeholder lint.
# Description: Lint scenario connections with the explicitly permitted idle GPU model.
#              No simulation is run and this is not GPU integration evidence.
# Clock domain: host.
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

out = ROOT / 'build/gpu_drivers/lint'
out.mkdir(parents=True, exist_ok=True)
for name in ('audio', 'eth', 'irq', 'render', 'reset'):
    files = expand_files(ROOT / f'verif/soc/gpu_{name}/files.f')
    # README explicitly permits this GPU replacement for lint only.
    files = [str(ROOT / 'verif/soc/gpu_common/edrv32_gpu.v')
             if path == str(ROOT / 'rtl/gpu/edrv32_gpu.v') else path for path in files]
    args = ['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
            '--top-module', 'edrv32_gpu_soc_tb'] + files
    with (out / f'{name}.log').open('w') as log:
        subprocess.run(args, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    print(f'PASS scenario lint gpu_{name} (idle GPU, no simulation)', flush=True)
