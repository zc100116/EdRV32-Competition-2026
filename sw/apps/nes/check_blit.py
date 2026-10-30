#!/usr/bin/env python3
# File: check_blit.py
# Spec: Task B3-4b step 2; rnd-spec 2.1/2.6; design rnd-disp 5.2.
# Description: Render the production I8 BLIT and compare every RGB565 pixel with 3x PPM.
# Clock domain: host.
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[3]
output = root / 'build/nes/blit-check'
output.mkdir(parents=True, exist_ok=True)
subprocess.run(['make', '-j1', '-C', str(root / 'sw/apps/nes')], check=True,
               stdout=(output / 'host-build.log').open('w'), stderr=subprocess.STDOUT)
with (output / 'host-run.log').open('w') as log:
    subprocess.run([str(root / 'build/sw/nes-host/nes-host'),
                    str(root / 'sw/apps/nes/roms/nrom-template.nes'), '180', str(output)],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
command = ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
           '-ffunction-sections', '-fdata-sections',
           '-I' + str(root / 'sw/apps/nes'), '-I' + str(root / 'sw/drivers/include'),
           '-I' + str(root / 'sw/bsp/include'),
           str(root / 'sw/apps/nes/tests/encode_host.c'),
           str(root / 'sw/apps/nes/display_command.c'), str(root / 'sw/drivers/rnd.c'),
           '-Wl,--gc-sections', '-o', str(output / 'encode-host')]
subprocess.run(command, check=True)
state_command = command[:command.index(str(root / 'sw/apps/nes/tests/encode_host.c'))]
state_command += ['-include', str(root / 'sw/apps/nes/tests/fake_mmio.h'),
                  str(root / 'sw/apps/nes/tests/display_host.c'),
                  str(root / 'sw/apps/nes/display.c'),
                  str(root / 'sw/apps/nes/display_command.c'),
                  str(root / 'sw/drivers/rnd.c'), str(root / 'sw/drivers/disp.c'),
                  str(root / 'sw/drivers/engine.c'), '-Wl,--gc-sections',
                  '-o', str(output / 'display-host')]
subprocess.run(state_command, check=True)
subprocess.run([str(output / 'display-host')], check=True)
with (output / 'frame-000180.ppm').open('rb') as ppm:
    assert ppm.readline() == b'P6\n'
    assert ppm.readline() == b'256 240\n'
    assert ppm.readline() == b'255\n'
    rgb = ppm.read()
colors = list(dict.fromkeys(rgb[i:i + 3] for i in range(0, len(rgb), 3)))
lookup = {color: i for i, color in enumerate(colors)}
indices = bytes(lookup[rgb[i:i + 3]] for i in range(0, len(rgb), 3))
palette = b''.join(colors) + bytes(3 * (256 - len(colors)))
encoded = subprocess.run([str(output / 'encode-host')], input=palette,
                         stdout=subprocess.PIPE, check=True).stdout
(output / 'blit.bin').write_bytes(encoded[:64])
(output / 'palette.argb').write_bytes(encoded[64:])
(output / 'frame.i8').write_bytes(indices)
spec = importlib.util.spec_from_file_location('rnd_ref', root / 'verif/block/rnd/rnd_ref.py')
ref = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = ref
spec.loader.exec_module(ref)
memory = bytearray(0x211000)
memory[0x200000:0x200000 + len(indices)] = indices
memory[0x210000:0x210400] = encoded[64:]
blit = ref.Command.decode(encoded[:64])
assert not blit.illegal()
ref.execute(memory, [blit])
preview = bytearray()
for y in range(720):
    for x in range(1280):
        expected = 0
        if 256 <= x < 1024:
            offset = ((y // 3) * 256 + (x - 256) // 3) * 3
            r, g, b = rgb[offset:offset + 3]
            expected = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        actual = struct.unpack_from('<H', memory, (y * 1280 + x) * 2)[0]
        if actual != expected:
            raise AssertionError(f'pixel ({x},{y}): expected {expected:#06x}, got {actual:#06x}')
        preview.extend(ref.e565(actual)[1:])
(output / 'display.ppm').write_bytes(b'P6\n1280 720\n255\n' + preview)
print('PASS NES BLIT: 921600 RGB565 pixels; exact 3x image, 256-pixel black side bars')
print(f'Artifacts: {output}')
