#!/usr/bin/env python3
"""Convert RISC-V ELF to Verilog hex format (32-bit words, MSB-first per line).
   Usage: python3 elf2hex.py input.elf output.hex"""
import struct, sys

with open(sys.argv[1], 'rb') as f:
    data = f.read()

with open(sys.argv[2], 'w') as out:
    for i in range(0, len(data), 4):
        word = struct.unpack('<I', data[i:i+4])[0]
        out.write(f'{word:08x}\n')
