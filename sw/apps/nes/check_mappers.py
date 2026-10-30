#!/usr/bin/env python3
# File: check_mappers.py
# Spec: Task T-NES3; mappers/ and tests/mappers.c.
# Description: Compile mapper interfaces with a bank/PPU test backend and check wiring.
# Clock domain: host.
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
out = root / 'build/nes/mappers-check'
out.mkdir(parents=True, exist_ok=True)
nof = root / 'third_party/nofrendo/components/nofrendo'
includes = [f'-I{root / "build/sw/nes-host/core/cpu"}'] + [
    f'-I{nof / p}' for p in ('', 'cpu', 'nes', 'sndhrdw', 'libsnss')]
includes.append(f'-I{root / "sw/apps/nes/mappers"}')
sources = sorted((root / 'sw/apps/nes/mappers').glob('*.c'))
subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', *includes,
                str(root / 'sw/apps/nes/tests/mappers.c'),
                str(root / 'build/sw/nes-host/core/mappers/map004.c'),
                *map(str, sources), '-o', str(out / 'mappers')], check=True)
subprocess.run([str(out / 'mappers')], check=True)
