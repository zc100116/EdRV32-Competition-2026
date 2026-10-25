#!/usr/bin/env python3
# File: elf2mem.py
# Spec: CLAUDE.md 9.2; infra-plan I-07
# Description: Convert RV32 ELF load-segment bytes into sparse byte memory images.
#              Use SoC region bases to produce ROM, SRAM and DDR offsets.
# Clock domain: none (host tool).
"""Split RV32 little-endian ELF load segments into byte-wide readmemh images."""
import argparse
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def convert(elf, output):
    blob = elf.read_bytes()
    # The software build contract is ELF32, little endian, for RISC-V.
    if blob[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError(f'{elf}: expected ELF32 little-endian input')
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', blob)
    regions = json.loads((ROOT / 'rtl/include/soc_address_map.json').read_text())['regions']
    images = {name: {} for name in ('rom', 'sram', 'ddr')}
    for index in range(header[10]):
        kind, offset, _vaddr, address, size, _memory_size, _flags, _align = (
            struct.unpack_from('<IIIIIIII', blob, header[5] + index * header[9]))
        if kind != 1 or size == 0:
            continue
        region = next(item for item in regions
                      if int(item['base'], 0) <= address
                      and address + size <= int(item['base'], 0) + int(item['size'], 0))
        name = region['name'].lower()
        if name not in images:
            raise ValueError(f'{elf}: load segment at 0x{address:08x} is not ROM/SRAM/DDR')
        base = address - int(region['base'], 0)
        images[name].update(enumerate(blob[offset:offset + size], base))
    output.mkdir(parents=True, exist_ok=True)
    for name, contents in images.items():
        lines = []
        previous = -2
        for address, value in sorted(contents.items()):
            if address != previous + 1:
                lines.append(f'@{address:08x}')
            lines.append(f'{value:02x}')
            previous = address
        (output / (name + '.hex')).write_text('\n'.join(lines) + ('\n' if lines else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    convert(args.elf, args.output)
