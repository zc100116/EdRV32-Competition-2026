#!/usr/bin/env python3
# File: run.py
# Spec: gpu-soc-testplan ST-11.
# Description: Prepare independent expectations and invoke the shared GPU SoC harness.
# Clock domain: host.
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from verif.soc.gpu_common.run import run
HERE = Path(__file__).resolve().parent
out = ROOT / 'build/gpu_soc' / HERE.name
out.mkdir(parents=True, exist_ok=True)
run(HERE, 11, software_sources='sw/tests/gpu_irq/main.c sw/drivers/gpu.c '
    'sw/drivers/aud.c sw/drivers/es8156.c sw/drivers/i2c.c '
    'sw/drivers/uart.c sw/drivers/plic.c sw/bsp/cache.c sw/tests/gpu_drivers/memory.c')
