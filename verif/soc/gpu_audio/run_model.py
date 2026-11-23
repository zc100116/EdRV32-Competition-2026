#!/usr/bin/env python3
# File: run_model.py
# Spec: gpu-soc-testplan ST-12 I2C recording model.
# Description: Compile and execute the focused I2C model self-check.
# Clock domain: host.
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[3]
out = ROOT / 'build/gpu_i2c_model'
out.mkdir(parents=True, exist_ok=True)
args = ['--timing', '-Wall', '--top-module', 'i2c_model_tb',
        'verif/models/i2c_rx_model.sv', 'verif/soc/gpu_audio/i2c_model_tb.sv']
subprocess.run(['verilator', '--lint-only'] + args, cwd=ROOT, check=True)
subprocess.run(['verilator', '--binary', '-j', '1', '--Mdir', str(out), '-o', 'sim'] + args,
               cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
subprocess.run([str(out / 'sim')], cwd=ROOT, check=True)
