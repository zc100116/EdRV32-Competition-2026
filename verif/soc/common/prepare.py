#!/usr/bin/env python3
# File: prepare.py
# Spec: soc-testplan SC-05/06, 4; vin 2.8, npu 2.4.
# Description: Generate DDR and independent CH2/NPU expected images for retained tests.
# Clock domain: host.
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from verif.block.vin.ch2 import reference as ch2_ref
from tools.npu.ref import npu_ref


def prepare(out, number):
    if number == 6:
        from network import prepare_network
        prepare_network(out)
        return
    pixels = ch2_ref.image(0)
    image = struct.pack('<' + 'H' * len(pixels), *pixels)
    segments = []
    if number == 5:
        expected = ch2_ref.process(pixels)
        (out / 'ch2.bin').write_bytes(expected)
        npu_dir = out / 'npu'
        subprocess.run([sys.executable, str(ROOT / 'tools/npu/gen_case.py'),
                        '--config', str(ROOT / 'verif/soc/sc_05_s1/npu.json'),
                        '--seed', '42', '--offset', '0', '--out', str(npu_dir)], check=True)
        memory = npu_ref.Memory()
        for path in sorted(npu_dir.glob('mem_*.hex')):
            memory.load_hex(path)
        memory.write(0x04000000, expected)
        # Feed the reference generated CH2 data; the random generator input is replaced.
        registers = {name: int(value, 16) for name, value in
                     map(str.split, (npu_dir / 'regs.txt').read_text().splitlines())}
        for address, page in sorted(memory.pages.items()):
            if not 0x04000000 <= address * 4096 < 0x04100000:
                segments.append((address * 4096, bytes(page)))
        npu_ref.execute(memory, registers)
        (out / 'npu.bin').write_bytes(memory.read(0x05000000, 320 * 192 * 16))
        if number == 5:
            segments.append((0x08000000, image))
    if segments:
        with (out / 'ddr.hex').open('w') as stream:
            for address, data in segments:
                stream.write(f'@{address:x}\n')
                stream.write(''.join(f'{b:02x}\n' for b in data))


if __name__ == '__main__':
    prepare(Path(sys.argv[1]), int(sys.argv[2]))
