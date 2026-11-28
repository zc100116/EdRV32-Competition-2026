#!/usr/bin/env python3
"""Validate the numerical SFU pieces; the ROM/reservation integration is pending."""
import subprocess
import sys
for script in ('run_prepare.py', 'run_scale.py'):
    subprocess.run([sys.executable, 'verif/unit/gpu2_sfu/' + script, *sys.argv[1:]], check=True)
subprocess.run([sys.executable, '-B', '-m', 'tools.gpu2.sfu'], check=True)
