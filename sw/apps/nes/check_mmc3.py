#!/usr/bin/env python3
# File: check_mmc3.py
# Spec: Task T-NES3; patches/mmc3-*.patch.
# Description: Exercise the patched MMC3 through its public mapintf_t callbacks.
# Clock domain: host.
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
out = root / 'build/nes/mmc3-check'
out.mkdir(parents=True, exist_ok=True)
nof = root / 'third_party/nofrendo/components/nofrendo'
includes = [f'-I{root / "build/sw/nes-host/core/cpu"}'] + [
    f'-I{nof / p}' for p in ('', 'cpu', 'nes', 'sndhrdw', 'libsnss')]
subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', *includes,
                str(root / 'sw/apps/nes/tests/mmc3_irq.c'),
                str(root / 'build/sw/nes-host/core/mappers/map004.c'),
                '-o', str(out / 'mmc3-irq')], check=True)
subprocess.run([str(out / 'mmc3-irq')], check=True)
