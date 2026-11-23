"""model/__main__.py — gpu-spec 8: execute a DDR image and export expected results.
Host command-line utility; no clock domain. Register writes execute in file order.
"""
import argparse
import json
import struct
from pathlib import Path

from ..scene import Memory
from . import GPU


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('registers', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--base', type=lambda value: int(value, 0), required=True)
    args = parser.parse_args()
    gpu = GPU(Memory.read_hex(args.image, args.base))
    gpu.execute(json.loads(args.registers.read_text()))
    args.output.mkdir(parents=True, exist_ok=True)
    for name, data in (('color', gpu.color), ('depth', gpu.depth), ('stencil', gpu.stencil)):
        # Explicit LE serialization, including on a big-endian Python host.
        fmt = '<B' if name == 'stencil' else '<H'
        (args.output / (name + '.bin')).write_bytes(b''.join(struct.pack(fmt, v) for v in data))
    gpu.memory.write_hex(args.output / 'ddr.hex')
    (args.output / 'registers.json').write_text(json.dumps(gpu.regs, indent=2) + '\n')


if __name__ == '__main__':
    main()
