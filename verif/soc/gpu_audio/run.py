#!/usr/bin/env python3
# File: run.py
# Spec: gpu-soc-testplan ST-12.
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
sine = [0, 1951, 3827, 5556, 7071, 8315, 9239, 9808,
        10000, 9808, 9239, 8315, 7071, 5556, 3827, 1951,
        0, -1951, -3827, -5556, -7071, -8315, -9239, -9808,
        -10000, -9808, -9239, -8315, -7071, -5556, -3827, -1951]
(out / 'audio.hex').write_text(''.join(
    f'{((10000 if i & 16 == 0 else -10000) & 65535) << 16 | (sine[i & 31] & 65535):08x}\n'
    for i in range(256)))
run(HERE, 12, software_sources='sw/tests/gpu_audio/main.c sw/drivers/gpu.c '
    'sw/drivers/aud.c sw/drivers/es8156.c sw/drivers/i2c.c '
    'sw/drivers/uart.c sw/drivers/plic.c sw/bsp/cache.c sw/tests/gpu_drivers/memory.c')
