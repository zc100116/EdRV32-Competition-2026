#!/usr/bin/env python3
# File: check_irq.py
# Spec: T-NES3; cpu-irq-lines and apu-frame-irq-ack patches.
# Description: Run the real patched CPU and APU frame-control acknowledgement.
# Clock domain: host.
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
out = root / 'build/nes/irq-check'
out.mkdir(parents=True, exist_ok=True)
nof = root / 'third_party/nofrendo/components/nofrendo'
core = root / 'build/sw/nes-host/core'
includes = [f'-I{core / "cpu"}'] + [f'-I{nof / p}' for p in
                                      ('', 'cpu', 'nes', 'sndhrdw', 'libsnss')]
subprocess.run(['gcc', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror',
                '-ffunction-sections', '-fdata-sections', *includes,
                str(root / 'sw/apps/nes/tests/irq_lines.c'), str(core / 'cpu/nes6502.c'),
                str(core / 'nes/nes.c'), '-Wl,--gc-sections', '-o', str(out / 'irq')], check=True)
subprocess.run([str(out / 'irq')], check=True)
