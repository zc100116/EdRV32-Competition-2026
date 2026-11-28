#!/usr/bin/env python3
"""Run the independent scalar and native vec4 scoreboards sequentially."""
import subprocess
import sys
for script in ('run.py', 'run_vec.py'):
    subprocess.run([sys.executable, 'verif/unit/gpu2_fp32/' + script, *sys.argv[1:]], check=True)
