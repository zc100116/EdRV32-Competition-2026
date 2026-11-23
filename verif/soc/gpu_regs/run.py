#!/usr/bin/env python3
# File: run.py
# Spec: gpu-soc-testplan ST-09.
# Description: Run the GPU SoC gpu_regs scenario through the shared harness.
# Clock domain: host.
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from verif.soc.gpu_common.run import run
run(Path(__file__).resolve().parent, 9,
    placeholder='--gpu-placeholder' in sys.argv, bios=False)
