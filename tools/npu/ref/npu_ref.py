#!/usr/bin/env python3
# File: npu_ref.py
# Spec: npu-spec 2.1–2.4, 4.1–4.3, 6; npu-testplan TL-01/TL-02.
# Description: Execute descriptor and memory images independently of the compiler.
#              Preserve exact integer quantization after vectorized convolution.
# Clock domain: none (host tool).
"""NPU functional reference model; all addresses are DDR byte addresses."""

import argparse
from dataclasses import dataclass
from pathlib import Path
import struct
import sys

import numpy as np


class Memory:
    """Sparse byte memory, stored in 4 KiB pages rather than per-byte objects."""

    def __init__(self):
        self.pages = {}

    def read(self, address, size):
        result = bytearray(size)
        offset = 0
        while offset < size:
            page, index = divmod(address + offset, 4096)
            count = min(size - offset, 4096 - index)
            if page in self.pages:
                result[offset:offset + count] = self.pages[page][index:index + count]
            offset += count
        return bytes(result)

    def write(self, address, data):
        offset = 0
        while offset < len(data):
            page, index = divmod(address + offset, 4096)
            count = min(len(data) - offset, 4096 - index)
            if page not in self.pages:
                self.pages[page] = bytearray(4096)
            self.pages[page][index:index + count] = data[offset:offset + count]
            offset += count

    def load_hex(self, path):
        address = 0
        segment = bytearray()
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith('@'):
                self.write(address, segment)
                address = int(line[1:], 16) * 32
                segment = bytearray()
            else:
                segment.extend(bytes.fromhex(line)[::-1])
        self.write(address, segment)

    def dump_hex(self, path, regions):
        with Path(path).open('w') as stream:
            for address, size in regions:
                stream.write(f'@{address // 32:x}\n')
                data = self.read(address, size)
                for offset in range(0, size, 32):
                    stream.write(data[offset:offset + 32][::-1].hex() + '\n')


@dataclass(frozen=True)
class Descriptor:
    words: tuple

    @classmethod
    def read(cls, memory, address):
        return cls(struct.unpack('<16I', memory.read(address, 64)))

    @property
    def op(self):
        return self.words[0] & 15

    def flag(self, bit):
        return bool(self.words[0] & (1 << bit))

    @property
    def kernel(self):
        return 3 if self.flag(4) else 1

    @property
    def step(self):
        return 2 if self.flag(5) else 1

    @property
    def input_shape(self):
        return ((self.words[8] >> 16) & 4095, self.words[8] & 4095)

    @property
    def output_shape(self):
        return ((self.words[9] >> 16) & 4095, self.words[9] & 4095)

    @property
    def cin_blocks(self):
        return self.words[10] & 63

    @property
    def cout_blocks(self):
        return (self.words[10] >> 8) & 15

    @property
    def zp(self):
        value = (self.words[10] >> 16) & 255
        return value - 256 if value >= 128 else value

    @property
    def output_channels(self):
        if self.op != 0:
            return 16 * self.cin_blocks
        return 32 * self.cout_blocks - (16 if self.flag(9) else 0)

    def address(self, bases, which):
        bit, word = {'input': (12, 1), 'output': (14, 3), 'residual': (16, 5)}[which]
        return bases[(self.words[0] >> bit) & 3] + self.words[word]

    def output_regions(self, bases):
        address = self.address(bases, 'output')
        height, width = self.output_shape
        return [(address + plane * self.words[4], height * width * 16)
                for plane in range(self.output_channels // 16)]


class NpuError(Exception):
    """The descriptor errors required by npu-spec section 6."""

    def __init__(self, err_code, cur_desc):
        self.err_code = err_code
        self.cur_desc = cur_desc
        super().__init__(f'ERR_CODE {err_code:08x}\nCUR_DESC {cur_desc:08x}')


def check_descriptor(desc, index):
    if desc.op not in (0, 1, 2):
        raise NpuError(3, index)
    # Coordinator clarification: raw fields only for these CONV capacity checks.
    # Never compare derived fields with their shape-derived equivalents.
    if desc.op == 0:
        row_slot_beats = desc.words[11] & 2047
        slots = 5 if desc.kernel == 3 else 2
        weight_block_bytes = desc.words[12] & 0xfffff
        if (slots * row_slot_beats > 1024 or desc.cout_blocks > 8
                or desc.cout_blocks * weight_block_bytes > 294912):
            raise NpuError(4, index)


def read_feature(memory, address, shape, planes, plane_stride, c4=False):
    height, width = shape
    if c4:
        return np.frombuffer(memory.read(address, height * width * 4), dtype=np.int8).reshape(
            height, width, 4)
    data = [np.frombuffer(memory.read(address + plane * plane_stride, height * width * 16),
                          dtype=np.int8).reshape(height, width, 16)
            for plane in range(planes)]
    return np.concatenate(data, axis=2)


def write_feature(memory, address, data, plane_stride):
    for plane in range(data.shape[2] // 16):
        memory.write(address + plane * plane_stride,
                     data[:, :, 16 * plane:16 * (plane + 1)].tobytes())


def decode_weights(memory, address, desc):
    """Decode each physical block type from spec 4.3 to [ky,kx,cin,cout]."""
    kernel = desc.kernel
    cin = 4 if desc.flag(8) else 16 * desc.cin_blocks
    channels = desc.output_channels
    weights = np.empty((kernel, kernel, cin, channels), dtype=np.int8)
    normal_rows = kernel * kernel * (1 if desc.flag(8) else 2 * desc.cin_blocks)
    for block in range(desc.cout_blocks):
        half = desc.flag(9) and block == desc.cout_blocks - 1
        count = 16 if half else 32
        base = address + block * normal_rows * 256
        if desc.flag(8):
            raw = np.frombuffer(memory.read(base, normal_rows * 256), dtype=np.int8)
            decoded = raw.reshape(kernel, kernel, 32, 8)[:, :, :count, :4]
            decoded = decoded.transpose(0, 1, 3, 2)
        elif half:
            raw = np.frombuffer(memory.read(base, normal_rows * 128), dtype=np.int8)
            decoded = raw.reshape(kernel, kernel, desc.cin_blocks, 2, 16, 8)
            decoded = decoded.transpose(0, 1, 2, 3, 5, 4).reshape(kernel, kernel, cin, 16)
        else:
            raw = np.frombuffer(memory.read(base, normal_rows * 256), dtype=np.int8)
            decoded = raw.reshape(kernel, kernel, desc.cin_blocks, 2, 32, 8)
            decoded = decoded.transpose(0, 1, 2, 3, 5, 4).reshape(kernel, kernel, cin, 32)
        weights[:, :, :, 32 * block:32 * block + count] = decoded
    return weights


def read_quant(memory, address, desc):
    records = np.frombuffer(memory.read(address, desc.cout_blocks * 512),
                            dtype=np.uint8).reshape(desc.cout_blocks, 512)
    parameters = records[:, :256].copy().reshape(-1, 8)[:desc.output_channels]
    bias = parameters[:, :4].copy().view('<i4').reshape(-1).astype(np.int64)
    mult = parameters[:, 4:6].copy().view('<i2').reshape(-1).astype(np.int64)
    shift = (parameters[:, 6] & 63).astype(np.int64)
    lut = records[:, 256:].copy().view(np.int8)
    return bias, mult, shift, lut


def quantize(acc, bias, mult, shift, zp, lut=None):
    """Spec 2.3: int64 holds all 33/49-bit intermediates without truncation."""
    shift = np.asarray(shift, dtype=np.int64)
    rounding = np.left_shift(np.int64(1), np.maximum(shift - 1, 0)) * (shift > 0)
    product = (np.asarray(acc, dtype=np.int64) + bias) * mult
    output = np.clip(np.right_shift(product + rounding, shift) + zp, -128, 127)
    if lut is not None:
        blocks = np.arange(output.shape[-1]) // 32
        output = lut[blocks, output & 255]
    return output.astype(np.int8)


def convolve(data, weights, output_shape, step):
    """Exact float64 dot products: supported INT8 reductions stay below 2**53."""
    kernel = weights.shape[0]
    padding = kernel // 2
    padded = np.pad(data, ((padding, padding), (padding, padding), (0, 0)))
    windows = np.lib.stride_tricks.sliding_window_view(padded, (kernel, kernel), axis=(0, 1))
    height, width = output_shape
    windows = windows[:height * step:step, :width * step:step]
    # The view is [y,x,cin,ky,kx]; reorder once to the independent weight decoder's order.
    windows = windows.transpose(0, 1, 3, 4, 2)
    matrix = weights.reshape(-1, weights.shape[-1]).astype(np.float64)
    result = np.empty((height, width, weights.shape[-1]), dtype=np.int64)
    rows_per_chunk = max(1, 1024 // width)
    for row in range(0, height, rows_per_chunk):
        end = min(row + rows_per_chunk, height)
        patch = windows[row:end].reshape((end - row) * width, -1).astype(np.float64)
        result[row:end] = (patch @ matrix).reshape(end - row, width, -1).astype(np.int64)
    return result


def execute_descriptor(memory, bases, desc):
    data = read_feature(memory, desc.address(bases, 'input'), desc.input_shape,
                        desc.cin_blocks, desc.words[2], desc.op == 0 and desc.flag(8))
    if desc.op == 0:
        weights = decode_weights(memory, bases[0] + desc.words[6], desc)
        acc = convolve(data, weights, desc.output_shape, desc.step)
        bias, mult, shift, lut = read_quant(memory, bases[0] + desc.words[7], desc)
        output = quantize(acc, bias, mult, shift, desc.zp, lut if desc.flag(6) else None)
        if desc.flag(7):
            residual = read_feature(memory, desc.address(bases, 'residual'), desc.output_shape,
                                    desc.output_channels // 16, desc.words[4])
            output = np.clip(output.astype(np.int16) + residual.astype(np.int16) - desc.zp,
                             -128, 127).astype(np.int8)
    elif desc.op == 1:
        padded = np.pad(data, ((2, 2), (2, 2), (0, 0)), constant_values=-128)
        windows = np.lib.stride_tricks.sliding_window_view(padded, (5, 5), axis=(0, 1))
        output = windows.max(axis=(-2, -1))
    else:
        output = data.repeat(2, axis=0).repeat(2, axis=1)
    write_feature(memory, desc.address(bases, 'output'), output, desc.words[4])


def execute(memory, registers, after_descriptor=None):
    bases = tuple(registers[name + '_BASE'] for name in ('MODEL', 'WORK', 'INPUT', 'OUTPUT'))
    for index in range(registers['DESC_COUNT']):
        desc = Descriptor.read(memory, registers['DESC_BASE'] + index * 64)
        check_descriptor(desc, index)
        execute_descriptor(memory, bases, desc)
        if after_descriptor is not None:
            after_descriptor(index, desc.output_regions(bases))


def load_case(directory):
    directory = Path(directory)
    registers = {name: int(value, 16)
                 for name, value in (line.split() for line in
                                     (directory / 'regs.txt').read_text().splitlines())}
    memory = Memory()
    for path in sorted(directory.glob('mem_*.hex')):
        memory.load_hex(path)
    return memory, registers


def run_case(directory, per_descriptor=False):
    directory = Path(directory)
    memory, registers = load_case(directory)

    def snapshot(index, regions):
        memory.dump_hex(directory / f'ref_desc_{index}.hex', regions)

    execute(memory, registers, snapshot if per_descriptor else None)
    regions = [(int(address, 16), int(size, 16)) for _, address, size in
               (line.split() for line in (directory / 'check.txt').read_text().splitlines())]
    memory.dump_hex(directory / 'ref_out.hex', regions)
    return memory


def split_case(directory, index, output_directory):
    """Export the complete state before descriptor index, then select that descriptor."""
    memory, registers = load_case(directory)
    prefix = dict(registers, DESC_COUNT=index)
    execute(memory, prefix)
    target_address = registers['DESC_BASE'] + index * 64
    target = Descriptor.read(memory, target_address)
    bases = tuple(registers[name + '_BASE'] for name in ('MODEL', 'WORK', 'INPUT', 'OUTPUT'))
    output_directory = Path(output_directory)
    output_directory.mkdir(parents=True)
    memory.dump_hex(output_directory / 'mem_state.hex',
                    [(page * 4096, 4096) for page in sorted(memory.pages)])
    registers.update(DESC_BASE=target_address, DESC_COUNT=1)
    (output_directory / 'regs.txt').write_text(''.join(
        f'{name} {value:08x}\n' for name, value in registers.items()))
    (output_directory / 'check.txt').write_text(''.join(
        f'plane_{plane} {address:08x} {size:x}\n'
        for plane, (address, size) in enumerate(target.output_regions(bases))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--per-desc', action='store_true', help='write ref_desc_<n>.hex too')
    parser.add_argument('--split-at', type=int, help='export state before zero-based descriptor N')
    parser.add_argument('--out', type=Path, help='new directory for --split-at')
    args = parser.parse_args()
    if args.split_at is not None and args.out is None:
        parser.error('--split-at requires --out')
    try:
        if args.split_at is None:
            run_case(args.directory, args.per_desc)
        else:
            split_case(args.directory, args.split_at, args.out)
    except NpuError as error:
        print(error)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
