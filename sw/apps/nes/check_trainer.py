#!/usr/bin/env python3
# File: check_trainer.py
# Spec: sw/apps/nes/README.md "ROM"; patches/rom-trainer-cursor.patch.
# Description: Wrap the repository NROM demo with a 512-byte iNES trainer and require
#              host frames identical to the plain ROM, proving PRG starts after it.
# Clock domain: host.
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
output = root / 'build/nes/trainer-check'
host = root / 'build/sw/nes-host/nes-host'
plain = root / 'sw/apps/nes/roms/nrom-template.nes'
output.mkdir(parents=True, exist_ok=True)
subprocess.run(['make', '-j1', '-C', str(root / 'sw/apps/nes')], check=True,
               stdout=(output / 'host-build.log').open('w'), stderr=subprocess.STDOUT)

image = plain.read_bytes()
header = bytearray(image[:16])
header[6] |= 0x04
trainer = output / 'nrom-template-trainer.nes'
trainer.write_bytes(bytes(header) + bytes([0xa5]) * 512 + image[16:])

for name, rom in (('plain', plain), ('trainer', trainer)):
    frames = output / name
    frames.mkdir(exist_ok=True)
    with (output / f'{name}.log').open('w') as log:
        subprocess.run([str(host), str(rom), '180', str(frames)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)

for frame in sorted((output / 'plain').glob('frame-*.ppm')):
    other = output / 'trainer' / frame.name
    if frame.read_bytes() != other.read_bytes():
        print(f'FAIL {frame.name}: trainer ROM frame differs from plain ROM')
        sys.exit(1)
print('PASS trainer ROM frames match plain ROM')
