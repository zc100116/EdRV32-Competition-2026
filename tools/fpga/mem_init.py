#!/usr/bin/env python3
# File: mem_init.py
# Spec: board-plan B1-3; sys-subsys-spec 2.2; CLAUDE.md 9.2.
# Description: Pack software byte images into full-depth PDS HEX initialization files.
#              The same 64-bit files can be loaded by the simulation memory wrappers.
# Clock domain: none (host tool).
"""Convert make's ROM/SRAM byte images to build/fpga/ip_{rom_boot,ram_sram}.dat."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def pack_image(source, depth, destination):
    """Read region-relative @byte addresses and emit ascending little-endian words."""
    memory = bytearray(depth * 8)
    address = 0
    for token in source.read_text().split():
        if token.startswith('@'):
            address = int(token[1:], 16)
        else:
            memory[address] = int(token, 16)
            address += 1
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(''.join(
        f'{int.from_bytes(memory[offset:offset + 8], "little"):016x}\n'
        for offset in range(0, len(memory), 8)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', type=Path, help='build/sw/bootloader/rom.hex')
    parser.add_argument('sram', type=Path, help='build/sw/monitor/sram.hex')
    args = parser.parse_args()
    pack_image(args.rom, 2048, ROOT / 'build/fpga/ip_rom_boot.dat')
    pack_image(args.sram, 8192, ROOT / 'build/fpga/ip_ram_sram.dat')


if __name__ == '__main__':
    main()
