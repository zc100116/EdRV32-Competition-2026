#!/usr/bin/env python3
"""Run the complete SFU reservation and numerical scoreboard."""
import subprocess
import sys
print('UNFROZEN G2-07: exceptional-value bits retain the IEEE development initial values.',
      flush=True)
subprocess.run([sys.executable, 'verif/unit/gpu2_sfu/run.py', *sys.argv[1:]], check=True)
