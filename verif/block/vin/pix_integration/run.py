#!/usr/bin/env python3
# File: run.py
# Spec: vin-testplan v0.2 VI-18; pix-spec 2.1-2.5.
# Description: Generate exact RGB565 inputs and independent PIX expectations, run serially.
# Clock domain: host.
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'verif/block/pix'))
from regress import expand_files
from pix_ref import process, gamma_tables


def main():
    out = ROOT / 'build/vin_pix'
    out.mkdir(parents=True, exist_ok=True)
    cfg = (2 << 4) | (4 << 8) | (1 << 17) | (1 << 18)
    for frame in range(4):
        pixels = [(0x9b61 ^ (frame * 0x3547) ^ (x * 73) ^ (y * 137)) & 65535
                  for y in range(16) for x in range(64)]
        expected = process(pixels, 64, 16, 1, cfg, 256, 128, gamma_tables())
        for name, values in ((f'in{frame}', pixels), (f'out{frame}', expected)):
            (out / f'{name}.hex').write_text(''.join(f'{p:04x}\n' for p in values))
    commands = [
        ['verilator', '--binary', '--timing', '-Wall', '-j', '1', '-CFLAGS', '-O0',
         '--top-module', 'edrv32_vin_pix_tb', '--Mdir', str(out / 'obj'), '-o', 'sim',
         '+define+SIM_MODE', *expand_files(Path(__file__).with_name('files.f'))],
        [str(out / 'obj/sim'), f'+DIR={out}'],
    ]
    for label, command in zip(('compile', 'run'), commands):
        log = out / f'{label}.log'
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream,
                                    stderr=subprocess.STDOUT, check=False)
        if result.returncode:
            print(log.read_text(), flush=True)
            raise RuntimeError(f'VI-18 {label} failed ({result.returncode}): {log}')
    print((out / 'run.log').read_text(), end='', flush=True)


if __name__ == '__main__':
    main()
