#!/usr/bin/env python3
# File: run.py; Spec: cpu-v2-testplan CV01/CV06/CV15; Clock: host.
"""Run the NONE CPU core smoke or short CoreMark measurement in both widths."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
mode = sys.argv[1]
subprocess.run([sys.executable, str(ROOT / 'tools/cpu/build_cpu2_tests.py'),
                '--suite', 'coremark' if mode == 'perf' else 'isa'], check=True)
for width in [1, 2]:
    command = [sys.executable, str(ROOT / 'tools/cpu/run_cpu2_core.py'), '--width', str(width)]
    if mode == 'perf':
        command += ['--program', 'coremark']
    subprocess.run(command, check=True)
print('PASS CPU2 NONE ' + mode)
