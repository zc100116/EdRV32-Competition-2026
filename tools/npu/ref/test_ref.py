#!/usr/bin/env python3
# File: test_ref.py
# Spec: npu-spec 2.1–2.4, 4.1–4.3, 6; npu-testplan TL-01/TL-02.
# Description: Independently pack images and compare vector operators to scalar formulas.
#              Directed quantization expectations are literal hand-calculated integers.
# Clock domain: none (host tool).
"""Reference-model self-tests; no compiler imports or compiler-generated fixtures."""

from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import numpy as np

import npu_ref as ref


BASES = (0x100000, 0x1000000, 0x4000000, 0x5000000)
DESC_BASE = 0x80000


def pack_feature(data):
    height, width, channels = data.shape
    # Test-side layout formula from 2.2, independent of reference feature helpers.
    packed = bytearray(height * width * channels)
    for channel in range(channels):
        for y in range(height):
            for x in range(width):
                index = (channel // 16 * height * width + y * width + x) * 16 + channel % 16
                packed[index] = int(data[y, x, channel]) & 255
    return packed


def store_feature(memory, address, data, stride):
    size = data.shape[0] * data.shape[1] * 16
    raw = pack_feature(data)
    for plane in range(data.shape[2] // 16):
        memory.write(address + plane * stride, raw[plane * size:(plane + 1) * size])


def load_feature(memory, address, shape, channels, stride):
    result = np.empty((*shape, channels), dtype=np.int8)
    for channel in range(channels):
        for y in range(shape[0]):
            for x in range(shape[1]):
                offset = channel // 16 * stride + (y * shape[1] + x) * 16 + channel % 16
                value = memory.read(address + offset, 1)[0]
                result[y, x, channel] = value - 256 if value >= 128 else value
    return result


def pack_weights(weights, c4, half_tail):
    channels, cin, kernel, _ = weights.shape
    blocks = (channels + 31) // 32
    result = bytearray()
    for block in range(blocks):
        half = half_tail and block == blocks - 1
        if c4:
            for ky in range(kernel):
                for kx in range(kernel):
                    for oc in range(32):
                        for k8 in range(8):
                            value = 0
                            if 32 * block + oc < channels and k8 < 4:
                                value = int(weights[32 * block + oc, k8, ky, kx])
                            result.append(value & 255)
        elif half:
            for ky in range(kernel):
                for kx in range(kernel):
                    for c16 in range(cin // 16):
                        for h in range(2):
                            for oc in range(16):
                                for k8 in range(8):
                                    value = weights[32 * block + oc, c16 * 16 + h * 8 + k8,
                                                    ky, kx]
                                    result.append(int(value) & 255)
        else:
            for ky in range(kernel):
                for kx in range(kernel):
                    for c16 in range(cin // 16):
                        for h in range(2):
                            for oc in range(32):
                                for k8 in range(8):
                                    value = weights[32 * block + oc, c16 * 16 + h * 8 + k8,
                                                    ky, kx]
                                    result.append(int(value) & 255)
    return result


def build_case(seed=0, shape=(4, 4), kernel=3, step=1, cin_blocks=1, cout_blocks=1,
               c4=False, half=False, lut_en=False, res_en=False, selectors=(2, 3, 1), op=0):
    rng = np.random.default_rng(seed)
    height, width = shape
    cin = 4 if c4 else cin_blocks * 16
    channels = (cout_blocks * 32 - (16 if half else 0)) if op == 0 else cin
    output_shape = ((height + step - 1) // step, (width + step - 1) // step)
    if op == 1:
        output_shape = shape
    elif op == 2:
        output_shape = (height * 2, width * 2)
    words = [0] * 16
    words[0] = (op | ((kernel == 3) << 4) | ((step == 2) << 5) | (lut_en << 6)
                | (res_en << 7) | (c4 << 8) | (half << 9) | (selectors[0] << 12)
                | (selectors[1] << 14) | (selectors[2] << 16))
    words[1] = 0x10000
    words[2] = 0 if c4 else height * width * 16 + 64
    words[3] = 0x100000
    words[4] = output_shape[0] * output_shape[1] * 16 + 96
    words[5] = 0x200000
    words[6] = 0x300000
    words[7] = 0x380000
    words[8] = width | (height << 16)
    words[9] = output_shape[1] | (output_shape[0] << 16)
    zp = -11
    words[10] = cin_blocks | (cout_blocks << 8) | ((zp & 255) << 16)
    reduction = kernel * kernel * (1 if c4 else 2 * cin_blocks)
    words[11] = cin_blocks * width // 4 | (reduction << 16)
    words[12] = reduction * 256
    data = rng.integers(-128, 128, (*shape, cin), dtype=np.int8)
    if c4:
        data[:, :, 3] = 0
    weights = rng.integers(-8, 8, (channels, cin, kernel, kernel), dtype=np.int8)
    bias = rng.integers(-1000, 1001, channels).tolist()
    mult = rng.integers(-7, 8, channels).tolist()
    shift = rng.integers(6, 15, channels).tolist()
    lut = rng.integers(-128, 128, (cout_blocks, 256), dtype=np.int8)
    residual = rng.integers(-128, 128, (*output_shape, channels), dtype=np.int8)
    memory = ref.Memory()
    memory.write(DESC_BASE, struct.pack('<16I', *words))
    if c4:
        memory.write(BASES[selectors[0]] + words[1], data.tobytes())
    else:
        store_feature(memory, BASES[selectors[0]] + words[1], data, words[2])
    if op == 0:
        memory.write(BASES[0] + words[6], pack_weights(weights, c4, half))
        records = bytearray()
        for block in range(cout_blocks):
            for oc in range(32):
                channel = block * 32 + oc
                if channel < channels:
                    records.extend(struct.pack('<ihBB', bias[channel], mult[channel],
                                               shift[channel], 0))
                else:
                    records.extend(bytes(8))
            records.extend(lut[block].tobytes())
        memory.write(BASES[0] + words[7], records)
        if res_en:
            store_feature(memory, BASES[selectors[2]] + words[5], residual, words[4])
    # Sentinel covers both plane gaps and the plane HALF_TAIL must leave unwritten.
    output_address = BASES[selectors[1]] + words[3]
    memory.write(output_address, bytes([0x5a]) * (words[4] * (channels // 16 + 1)))
    registers = {name + '_BASE': address for name, address in
                 zip(('MODEL', 'WORK', 'INPUT', 'OUTPUT'), BASES)}
    registers.update(DESC_BASE=DESC_BASE, DESC_COUNT=1)
    case = dict(data=data, weights=weights, bias=bias, mult=mult, shift=shift, zp=zp,
                lut=lut, residual=residual, kernel=kernel, step=step, output_shape=output_shape,
                channels=channels, lut_en=lut_en, res_en=res_en, op=op, words=words,
                output_address=output_address)
    return memory, registers, case


def naive(case):
    """Pure Python operator arithmetic written directly from spec 2.1 and 2.3."""
    data = case['data'].tolist()
    weights = case['weights'].tolist()
    residual = case['residual'].tolist()
    lut = case['lut'].tolist()
    height, width, cin = case['data'].shape
    out_h, out_w = case['output_shape']
    channels = case['channels']
    output = [[[0 for _ in range(channels)] for _ in range(out_w)] for _ in range(out_h)]
    for y in range(out_h):
        for x in range(out_w):
            for channel in range(channels):
                if case['op'] == 0:
                    acc = 0
                    for ky in range(case['kernel']):
                        iy = y * case['step'] + ky - case['kernel'] // 2
                        for kx in range(case['kernel']):
                            ix = x * case['step'] + kx - case['kernel'] // 2
                            if 0 <= iy < height and 0 <= ix < width:
                                for ci in range(cin):
                                    acc += data[iy][ix][ci] * weights[channel][ci][ky][kx]
                    t = (acc + case['bias'][channel]) * case['mult'][channel]
                    shift = case['shift'][channel]
                    u = (t + ((1 << (shift - 1)) if shift > 0 else 0)) >> shift
                    value = max(-128, min(127, u + case['zp']))
                    if case['lut_en']:
                        value = lut[channel // 32][value & 255]
                    if case['res_en']:
                        value = max(-128, min(127, value + residual[y][x][channel] - case['zp']))
                elif case['op'] == 1:
                    value = -128
                    for ky in range(-2, 3):
                        for kx in range(-2, 3):
                            if 0 <= y + ky < height and 0 <= x + kx < width:
                                value = max(value, data[y + ky][x + kx][channel])
                else:
                    value = data[y // 2][x // 2][channel]
                output[y][x][channel] = value
    return np.array(output, dtype=np.int8)


def write_case(directory, memory, registers, case):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'regs.txt').write_text(''.join(f'{name} {value:08x}\n'
                                              for name, value in registers.items()))
    # Separate image segments are not semantically significant; all fixture data is in model.
    memory.dump_hex(directory / 'mem_model.hex', [(page * 4096, 4096)
                                                for page in sorted(memory.pages)])
    size = case['words'][4] * (case['channels'] // 16 + 1)
    (directory / 'check.txt').write_text(f"result {case['output_address']:08x} {size:x}\n")


def create_demo(directory):
    memory, registers, case = build_case(seed=2026, shape=(4, 8), kernel=3)
    write_case(directory, memory, registers, case)


class QuantizationTests(unittest.TestCase):
    def test_tl01_literal_formula_boundaries(self):
        # (acc, bias, mult, shift, zp, expected); all expectations calculated by hand.
        vectors = [
            (7, -2, -3, 0, 0, -15),
            (3, 0, 1, 1, 0, 2),
            (-3, 0, 1, 1, 0, -1),
            (-1, 0, 1, 1, 0, 0),
            (0, 0, -32768, 47, -7, -7),
            (-2147483648, -2147483648, -32768, 47, 0, 1),
            (2147483647, 2147483647, 32767, 47, 0, 1),
            (-2147483648, -2147483648, 32767, 47, 0, -1),
            (2147483647, 2147483647, -32768, 47, 0, -1),
            (2147483647, 1, 1, 25, 0, 64),
            (-2147483648, -2147483648, -32768, 42, 0, 32),
            (2147483647, 0, 32767, 0, -128, 127),
            (-2147483648, 0, 32767, 0, 127, -128),
            (120, 0, 1, 0, 20, 127),
            (-120, 0, 1, 0, -20, -128),
            (1, -2147483648, -1, 25, 0, 64),
        ]
        for acc, bias, mult, shift, zp, expected in vectors:
            with self.subTest(vector=(acc, bias, mult, shift, zp)):
                actual = ref.quantize(np.array([acc]), np.array([bias]), np.array([mult]),
                                      np.array([shift]), zp)
                self.assertEqual(int(actual[0]), expected)

    def test_tl01_lut_unsigned_indices(self):
        lut = np.zeros((1, 256), dtype=np.int8)
        lut[0, [0, 127, 128, 255]] = [11, -22, 33, -44]
        actual = ref.quantize(np.array([0, 127, -128, -1]), np.zeros(4, dtype=np.int64),
                              np.ones(4, dtype=np.int64), np.zeros(4, dtype=np.int64), 0, lut)
        np.testing.assert_array_equal(actual, [11, -22, 33, -44])


class OperatorTests(unittest.TestCase):
    def compare(self, **options):
        memory, registers, case = build_case(**options)
        expected = naive(case)
        ref.execute(memory, registers)
        actual = load_feature(memory, case['output_address'], case['output_shape'],
                              case['channels'], case['words'][4])
        np.testing.assert_array_equal(actual, expected)
        plane_size = np.prod(case['output_shape']) * 16
        stride = case['words'][4]
        for plane in range(case['channels'] // 16):
            gap = case['output_address'] + plane * stride + int(plane_size)
            self.assertEqual(memory.read(gap, stride - plane_size), b'\x5a' * (stride - plane_size))
        self.assertEqual(memory.read(case['output_address'] + case['channels'] // 16 * stride,
                                     stride), b'\x5a' * stride)

    def test_tl02_conv_all_flags_random_seeds(self):
        # All K3/S2/LUT/RES/HALF combinations, with independent seeds and shapes.
        for seed in range(3):
            for bits in range(32):
                options = dict(seed=100 * seed + bits, shape=[(4, 4), (5, 8), (8, 16)][seed],
                               kernel=3 if bits & 1 else 1, step=2 if bits & 2 else 1,
                               lut_en=bool(bits & 4), res_en=bool(bits & 8), half=bool(bits & 16))
                with self.subTest(**options):
                    self.compare(**options)

    def test_tl02_multiple_input_and_output_blocks(self):
        for seed in range(3):
            for kernel in (1, 3):
                with self.subTest(seed=seed, kernel=kernel):
                    self.compare(seed=seed + 70, shape=(4, 12), kernel=kernel,
                                 cin_blocks=seed + 1, cout_blocks=3, half=bool(seed % 2),
                                 lut_en=True, res_en=True)

    def test_tl02_c4_normal_and_single_plane(self):
        for seed in range(3):
            for half in (False, True):
                with self.subTest(seed=seed, half=half):
                    self.compare(seed=seed, shape=(4, 8), kernel=3, step=2, c4=True,
                                 half=half, lut_en=True, res_en=True)

    def test_tl02_all_base_selectors_and_offsets(self):
        for source in range(4):
            with self.subTest(source=source):
                self.compare(seed=source, selectors=(source, (source + 1) % 4,
                                                     (source + 2) % 4), res_en=True)

    def test_tl02_pool_random(self):
        for seed, shape in enumerate(((4, 4), (6, 12), (8, 16))):
            with self.subTest(seed=seed):
                self.compare(seed=seed, shape=shape, cin_blocks=seed + 1, op=1)

    def test_tl02_pool_negative_padding(self):
        memory, registers, case = build_case(shape=(4, 4), cin_blocks=2, op=1)
        case['data'][:] = -128
        case['data'][1, 1] = -73
        store_feature(memory, BASES[2] + case['words'][1], case['data'], case['words'][2])
        ref.execute(memory, registers)
        actual = load_feature(memory, case['output_address'], (4, 4), 32, case['words'][4])
        np.testing.assert_array_equal(actual, naive(case))

    def test_tl02_upsample_random(self):
        for seed, shape in enumerate(((4, 4), (6, 12), (8, 16))):
            with self.subTest(seed=seed):
                self.compare(seed=seed, shape=shape, cin_blocks=seed + 1, op=2)

    def test_shape_arithmetic_ignores_derived_fields(self):
        memory, registers, case = build_case(shape=(4, 8), cout_blocks=3, half=True)
        case['words'][11] = 1 | (1 << 16)
        case['words'][12] = 1
        memory.write(DESC_BASE, struct.pack('<16I', *case['words']))
        ref.execute(memory, registers)
        actual = load_feature(memory, case['output_address'], case['output_shape'],
                              case['channels'], case['words'][4])
        np.testing.assert_array_equal(actual, naive(case))

    def test_descriptor_sequence(self):
        memory, registers, case = build_case(shape=(4, 8), half=True)
        first_expected = naive(case)
        words = case['words'].copy()
        words[0] = 2 | (3 << 12) | (1 << 14)
        words[1] = case['words'][3]
        words[2] = case['words'][4]
        words[3] = 0x400000
        words[4] = 8 * 16 * 16 + 64
        words[9] = 16 | (8 << 16)
        words[10] = 1
        memory.write(DESC_BASE + 64, struct.pack('<16I', *words))
        registers['DESC_COUNT'] = 2
        snapshots = []
        ref.execute(memory, registers, lambda index, regions: snapshots.append(
            (index, [memory.read(address, size) for address, size in regions])))
        actual = load_feature(memory, BASES[1] + words[3], (8, 16), 16, words[4])
        np.testing.assert_array_equal(actual, first_expected.repeat(2, 0).repeat(2, 1))
        self.assertEqual([index for index, _ in snapshots], [0, 1])
        self.assertEqual(snapshots[0][1][0], bytes(pack_feature(first_expected)))


class ErrorAndFileTests(unittest.TestCase):
    def test_spec6_invalid_ops_and_three_capacity_errors_stop(self):
        cases = [('op3', 0, 3, 3), ('op15', 0, 15, 3),
                 ('row3', 11, 205, 4), ('row1', 11, 513, 4),
                 ('cout', 10, 1 | (9 << 8), 4), ('weight', 12, 294913, 4)]
        for name, field, value, code in cases:
            with self.subTest(name=name):
                memory, registers, case = build_case()
                if name == 'row1':
                    case['words'][0] &= ~(1 << 4)
                case['words'][field] = value
                # A successful first descriptor establishes zero-based CUR_DESC.
                memory.write(DESC_BASE + 64, struct.pack('<16I', *case['words']))
                registers['DESC_COUNT'] = 3
                with self.assertRaises(ref.NpuError) as caught:
                    ref.execute(memory, registers)
                self.assertEqual((caught.exception.err_code, caught.exception.cur_desc), (code, 1))

    def test_spec6_capacity_equal_limits(self):
        for row, k3 in ((512, False), (204, True)):
            words = [0] * 16
            words[0] = int(k3) << 4
            words[10] = 8 << 8
            words[11] = row
            words[12] = 36864
            ref.check_descriptor(ref.Descriptor(tuple(words)), 0)
        # 5*ROW_SLOT_BEATS=1024 is unrepresentable; 204 is largest legal K3 field.

    def test_sparse_memory_endianness_and_page_crossing(self):
        memory = ref.Memory()
        self.assertEqual(memory.read(0x1234, 32), bytes(32))
        data = bytes(range(96))
        memory.write(4096 - 32, data)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mem_input.hex'
            memory.dump_hex(path, [(4096 - 32, 96), (0x10000, 32)])
            lines = path.read_text().splitlines()
            self.assertEqual(lines[0], '@7f')
            self.assertEqual(lines[1], bytes(range(32))[::-1].hex())
            restored = ref.Memory()
            restored.load_hex(path)
            self.assertEqual(restored.read(4096 - 32, 96), data)

    def test_cli_fixture_and_snapshots(self):
        with tempfile.TemporaryDirectory() as directory:
            memory, registers, case = build_case(seed=2026, shape=(4, 8), kernel=3)
            expected = naive(case)
            write_case(directory, memory, registers, case)
            result = subprocess.run([sys.executable, str(Path(ref.__file__)), directory,
                                     '--per-desc'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            restored = ref.Memory()
            restored.load_hex(Path(directory) / 'ref_out.hex')
            actual = load_feature(restored, case['output_address'], case['output_shape'],
                                  case['channels'], case['words'][4])
            np.testing.assert_array_equal(actual, expected)
            snapshot = ref.Memory()
            snapshot.load_hex(Path(directory) / 'ref_desc_0.hex')
            np.testing.assert_array_equal(load_feature(snapshot, case['output_address'],
                                                       case['output_shape'], case['channels'],
                                                       case['words'][4]), expected)

    def test_cli_error_report(self):
        with tempfile.TemporaryDirectory() as directory:
            memory, registers, case = build_case()
            case['words'][0] = 15
            memory.write(DESC_BASE, struct.pack('<16I', *case['words']))
            write_case(directory, memory, registers, case)
            result = subprocess.run([sys.executable, str(Path(ref.__file__)), directory],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, 'ERR_CODE 00000003\nCUR_DESC 00000000\n')
            self.assertFalse((Path(directory) / 'ref_out.hex').exists())

    def test_cli_split_before_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            memory, registers, case = build_case(seed=91, shape=(4, 8), half=True)
            words = case['words'].copy()
            words[0] = 1 | (3 << 12) | (1 << 14)
            words[1] = case['words'][3]
            words[2] = case['words'][4]
            words[3] = 0x400000
            words[10] = 1
            memory.write(DESC_BASE + 64, struct.pack('<16I', *words))
            registers['DESC_COUNT'] = 2
            write_case(source, memory, registers, case)
            for index in (0, 1):
                with self.subTest(index=index):
                    output = Path(directory) / f'split_{index}'
                    command = [sys.executable, str(Path(ref.__file__)), str(source),
                               '--split-at', str(index), '--out', str(output)]
                    result = subprocess.run(command, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual({path.name for path in output.iterdir()},
                                     {'mem_state.hex', 'regs.txt', 'check.txt'})
                    extracted, extracted_regs = ref.load_case(output)
                    self.assertEqual(extracted_regs['DESC_COUNT'], 1)
                    self.assertEqual(extracted_regs['DESC_BASE'], DESC_BASE + 64 * index)
                    prefix, prefix_regs = ref.load_case(source)
                    prefix_regs['DESC_COUNT'] = index
                    ref.execute(prefix, prefix_regs)
                    self.assertEqual(extracted.pages, prefix.pages)
                    ref.run_case(output)
                    self.assertTrue((output / 'ref_out.hex').exists())
                    if index == 1:
                        chained = dict(case, data=naive(case), op=1)
                        expected = naive(chained)
                        actual_memory = ref.Memory()
                        actual_memory.load_hex(output / 'ref_out.hex')
                        actual = load_feature(actual_memory, BASES[1] + words[3],
                                              case['output_shape'], 16, words[4])
                        np.testing.assert_array_equal(actual, expected)


if __name__ == '__main__':
    unittest.main()
