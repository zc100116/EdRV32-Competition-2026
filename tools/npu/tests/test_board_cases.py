#!/usr/bin/env python3
# File: test_board_cases.py
# Spec: npu-spec 2.2, 4.1; board-npu-test design section 4.
# Description: Check sparse byte order, relocated payloads, stride padding and
#              failure reporting when packed reference bytes are corrupted.
# Clock domain: none (host tool).
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import board_cases
from format import BASES, Descriptor, write_case, write_hex


class BoardCasesTest(unittest.TestCase):
    def setUp(self):
        output = board_cases.ROOT / 'build'
        output.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=output)
        self.directory = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def test_sparse_hex_byte_order(self):
        path = self.directory / 'mem_input.hex'
        segments = [(0x1000, bytes(range(32))), (0x4000, bytes(reversed(range(32))))]
        write_hex(path, segments)
        self.assertEqual(list(board_cases.hex_segments(path)), segments)

    def make_case(self):
        desc = Descriptor(op=2, in_sel=2, out_sel=3, in_offset=32, out_offset=64,
                          in_w=2, in_h=1, out_w=4, out_h=2, cin_blocks=1,
                          cout_blocks=0, in_plane_stride=32, out_plane_stride=160)
        write_case(self.directory, [desc],
                   {'input': [(BASES['INPUT_BASE'] + 32, bytes(range(32)))]},
                   [('output', BASES['OUTPUT_BASE'] + 64, 160)])
        blob = bytearray()
        case = board_cases.pack_case(self.directory, 'upsample', blob)
        return case, blob

    def test_relocation_and_stride_padding(self):
        case, blob = self.make_case()
        self.assertEqual(case['config'][0], BASES['MODEL_BASE'] + board_cases.RUNTIME_BIAS)
        address, offset, size, producer = case['checks'][0]
        self.assertEqual(address, BASES['OUTPUT_BASE'] + board_cases.RUNTIME_BIAS + 64)
        self.assertEqual((size, producer), (160, 0))
        pixel0, pixel1 = bytes(range(16)), bytes(range(16, 32))
        row = pixel0 * 2 + pixel1 * 2
        self.assertEqual(blob[offset:offset + size], row * 2 + bytes(32))
        with contextlib.redirect_stdout(io.StringIO()):
            board_cases.self_check(case, bytes(blob))

    def test_corrupt_expected_byte_reports_first_address_and_total(self):
        case, blob = self.make_case()
        address, offset, _, _ = case['checks'][0]
        blob[offset + 17] ^= 1
        with self.assertRaisesRegex(ValueError,
                                    f'desc=0 addr={address + 17:08x} .*mismatches=1'):
            board_cases.self_check(case, bytes(blob))


if __name__ == '__main__':
    unittest.main()
