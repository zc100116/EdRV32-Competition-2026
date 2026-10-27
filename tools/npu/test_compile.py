"""test_compile.py — NPU testplan TL-03; spec 2.2, 4.1–4.3.

Directed byte/bit positions use the design record 4.7.5 examples.
Clock domain: offline host unittest.
"""

from collections import Counter
from pathlib import Path
from types import SimpleNamespace
import struct
import tempfile
import unittest

import numpy as np

from fixed_plan import build_plan, descriptors
from gen_case import Case, configured
from format import Descriptor, pack_c4, pack_c16, pack_quant, pack_weights, write_hex


class DescriptorTest(unittest.TestCase):
    def test_field_positions(self):
        desc = Descriptor(
            k3=True, s2=True, lut_en=True, res_en=True, in_c4=True, half_tail=True,
            in_sel=2, out_sel=3, res_sel=1, in_offset=0x120, in_plane_stride=0,
            out_offset=0x340, out_plane_stride=0x600, res_offset=0x780,
            weight_offset=0x9a0, quant_offset=0xbc0,
            in_w=16, in_h=9, out_w=8, out_h=5, cin_blocks=1, cout_blocks=1, out_zp=-17)
        words = struct.unpack("<16I", desc.encode())
        self.assertEqual(words, (
            0x0001e3f0, 0x120, 0, 0x340, 0x600, 0x780, 0x9a0, 0xbc0,
            0x00090010, 0x00050008, 0x00ef0101, 0x00090004, 2304, 0, 0, 0))
        self.assertEqual(desc.encode()[40:44], bytes.fromhex("0101ef00"))

    def test_derived_fields(self):
        cases = [
            # cin, k3, c4, cout blocks, half, row, K, block bytes, actual bytes
            (1, True, False, 1, False, 4, 18, 4608, 4608),
            (1, True, False, 1, True, 4, 18, 4608, 2304),
            (1, True, True, 1, True, 4, 9, 2304, 2304),
            (3, False, False, 3, True, 12, 6, 1536, 3840),
            (8, True, False, 8, False, 32, 144, 36864, 294912),
        ]
        for cin, k3, c4, cout, half, row, count, block, actual in cases:
            with self.subTest(cin=cin, c4=c4, half=half):
                desc = Descriptor(in_w=16, cin_blocks=cin, k3=k3, in_c4=c4,
                                  cout_blocks=cout, half_tail=half)
                words = struct.unpack("<16I", desc.encode())
                self.assertEqual(words[11], row | count << 16)
                self.assertEqual(words[12], block)
                self.assertEqual(desc.weight_bytes, actual)

    def test_pool_upsample_shapes(self):
        for op, width, height in [(1, 8, 5), (2, 16, 10)]:
            desc = Descriptor(op=op, in_w=8, in_h=5, out_w=width, out_h=height,
                              cin_blocks=3, cout_blocks=0)
            words = struct.unpack("<16I", desc.encode())
            self.assertEqual(words[0] & 15, op)
            self.assertEqual(words[9], width | height << 16)
            self.assertEqual(words[10:13], (3, 6, 0))

    def test_network_plan(self):
        plan = build_plan()
        rows = [{"index": c["index"], "output_zero_point": 0}
                for c in plan["commands"] if c["kind"] == "conv"]
        encoded = descriptors(plan, rows)
        self.assertEqual(Counter(d.op for d in encoded), {0: 63, 1: 3, 2: 2})
        self.assertEqual(sum(d.res_en for d in encoded), 6)
        first = encoded[0]
        self.assertEqual((first.in_c4, first.half_tail, first.cout_blocks,
                          first.in_plane_stride, first.k_count), (True, True, 1, 0, 9))
        tensors = plan["tensors"]
        for left, right in [("L10", "L6"), ("L13", "L4"),
                            ("L16", "L12"), ("L19", "L9")]:
            self.assertEqual(tensors[left]["base"] + tensors[left]["bytes"],
                             tensors[right]["base"])
            self.assertEqual(tensors[left]["plane_stride"], tensors[right]["plane_stride"])
        for desc in encoded:
            self.assertEqual(desc.out_plane_stride % 32, 0)
            if desc.op == 0:
                self.assertLessEqual(desc.cout_blocks * desc.weight_block_bytes, 294912)
                self.assertLessEqual(desc.cin_blocks * desc.in_w // 4 *
                                     (5 if desc.k3 else 2), 1024)
        heads = [d for d in encoded if d.out_sel == 3]
        self.assertEqual(len(heads), 6)
        self.assertTrue(all(not d.lut_en for d in heads))


class WeightLayoutTest(unittest.TestCase):
    @staticmethod
    def weights(cout, cin):
        return np.fromfunction(lambda oc, ic, ky, kx:
                               (oc * 31 + ic * 7 + ky * 3 + kx) % 256 - 128,
                               (cout, cin, 3, 3), dtype=int).astype(np.int8)

    def test_ordinary_475(self):
        weight = self.weights(32, 16)
        packed = pack_weights(weight, Descriptor(k3=True))
        self.assertEqual(len(packed), 4608)
        examples = [(0, 0, 0, 0, 0), (8, 1, 0, 0, 0),
                    (16, 2, 0, 0, 0), (24, 3, 0, 0, 0),
                    (32, 4, 0, 0, 0), (40, 5, 0, 0, 0),
                    (248, 31, 0, 0, 0), (256, 0, 8, 0, 0),
                    (264, 1, 8, 0, 0), (512, 0, 0, 0, 1),
                    (1536, 0, 0, 1, 0), (4600, 31, 8, 2, 2)]
        for offset, oc, ic, ky, kx in examples:
            with self.subTest(offset=offset):
                self.assertEqual(packed[offset:offset + 8], weight[oc, ic:ic + 8, ky, kx].tobytes())

    def test_half_tail_475(self):
        weight = self.weights(16, 16)
        packed = pack_weights(weight, Descriptor(k3=True, half_tail=True))
        self.assertEqual(len(packed), 2304)
        for offset, oc, ic, ky, kx in [(0, 0, 0, 0, 0), (120, 15, 0, 0, 0),
                                      (128, 0, 8, 0, 0), (256, 0, 0, 0, 1),
                                      (2296, 15, 8, 2, 2)]:
            self.assertEqual(packed[offset:offset + 8], weight[oc, ic:ic + 8, ky, kx].tobytes())

    def test_third_block_half_tail(self):
        weight = self.weights(80, 16)
        packed = pack_weights(weight, Descriptor(k3=True, cout_blocks=3, half_tail=True))
        self.assertEqual(len(packed), 11520)
        self.assertEqual(packed[9216:9224], weight[64, :8, 0, 0].tobytes())
        self.assertEqual(packed[9344:9352], weight[64, 8:16, 0, 0].tobytes())

    def test_c4_475(self):
        for cout in (16, 32):
            weight = self.weights(cout, 3)
            desc = Descriptor(k3=True, in_c4=True, half_tail=cout == 16)
            packed = pack_weights(weight, desc)
            self.assertEqual(len(packed), 2304)
            for offset, oc, ky, kx in [(0, 0, 0, 0), (8, 1, 0, 0), (256, 0, 0, 1)]:
                self.assertEqual(packed[offset:offset + 3], weight[oc, :3, ky, kx].tobytes())
                self.assertEqual(packed[offset + 3:offset + 8], bytes(5))
            if cout == 16:
                for row in range(9):
                    self.assertEqual(packed[row * 256 + 128:(row + 1) * 256], bytes(128))


class QuantAndFeatureTest(unittest.TestCase):
    def test_quant_records(self):
        lut = np.arange(256, dtype=np.uint8).tobytes()
        bias = [-2147483648, 2147483647] + [0] * 31
        mult = [-32768, 32767] + [-1] * 31
        shift = [0, 47] + [1] * 31
        data = pack_quant(bias, mult, shift, 2, lut)
        self.assertEqual(len(data), 1024)
        self.assertEqual(data[:16], bytes.fromhex("0000008000800000ffffff7fff7f2f00"))
        self.assertEqual(struct.unpack_from("<ihBB", data, 512), (0, -1, 1, 0))
        for block in (0, 1):
            self.assertEqual(data[block * 512 + 256:(block + 1) * 512], lut)
            self.assertTrue(all(data[block * 512 + ch * 8 + 7] == 0 for ch in range(32)))
        self.assertEqual(data[520:768], bytes(248))

    def test_c4_rgb_and_hex(self):
        rgb = np.array([[[1, 2, 3], [-128, 127, -1]] * 4], dtype=np.int8)
        data = pack_c4(rgb)
        self.assertEqual(data, bytes.fromhex("01020300807fff00") * 4)
        root = Path(__file__).resolve().parents[2] / "build/npu"
        root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as directory:
            path = Path(directory) / "mem_input.hex"
            write_hex(path, [(0x04000020, data)])
            self.assertEqual(path.read_text().splitlines(), [
                "@00200001", "00ff7f8000030201" * 4])

    def test_c16_plane_padding(self):
        chw = np.arange(32 * 2 * 4, dtype=np.int16).astype(np.int8).reshape(32, 2, 4)
        packed = pack_c16(chw, 160)
        self.assertEqual(len(packed), 320)
        self.assertEqual(packed[:16], chw[:16, 0, 0].tobytes())
        self.assertEqual(packed[16:32], chw[:16, 0, 1].tobytes())
        self.assertEqual(packed[128:160], bytes(32))
        self.assertEqual(packed[160:176], chw[16:, 0, 0].tobytes())


class ConfigCaseTest(unittest.TestCase):
    def test_concat_residual_and_directed_quant(self):
        root = Path(__file__).resolve().parents[2] / "build/npu"
        root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as directory:
            args = SimpleNamespace(offset=32, seed=29, plane_pad=0,
                                   quant_boundaries=False, out=Path(directory))
            case = Case(args, {"MODEL_BASE": 0x200000, "DESC_BASE": 0xc0000})
            configured(case, [
                {"op": "conv", "in_w": 4, "in_h": 4, "cin": 16, "cout": 16,
                 "in_sel": "model", "in_offset": "0x4000", "out_offset": "0x1000",
                 "out_plane_stride": "0x140", "weights": "max",
                 "quant": {"bias": -2147483648, "mult": -32768,
                           "shift": 47, "out_zp": -12}},
                {"op": "conv", "in_from": "input", "in_w": 4, "in_h": 4,
                 "cin": 16, "cout": 16, "in_sel": "model", "in_offset": "0x4000",
                 "out_offset": "0x1140", "out_plane_stride": "0x140", "weights": "min"},
                {"op": "conv", "in_from": [0, 1], "cout": 16, "out_sel": "output",
                 "out_offset": "0x2000", "out_plane_stride": "0x140",
                 "res": True, "res_from": 0, "half_tail": True},
            ])
            first, second, third = case.descriptors
            self.assertEqual((first.in_sel, first.in_offset), (0, 0x4000))
            self.assertEqual((first.out_sel, first.out_offset, first.out_plane_stride),
                             (1, 0x1000, 0x140))
            self.assertEqual(second.out_offset, 0x1140)
            self.assertEqual((third.in_sel, third.in_offset, third.in_plane_stride,
                              third.cin_blocks), (1, 0x1000, 0x140, 2))
            self.assertEqual((third.res_en, third.res_sel, third.res_offset),
                             (True, 1, 0x1000))
            model_segments = dict(case.segments["model"])
            first_data = model_segments[0x200000 + first.weight_offset]
            self.assertEqual(first_data[:first.weight_bytes], bytes([127]) * 256)
            self.assertEqual(struct.unpack_from("<ihBB", first_data, 256),
                             (-2147483648, -32768, 47, 0))
            self.assertEqual(first.out_zp, -12)
            self.assertIn("DESC_BASE 000c0000", (args.out / "regs.txt").read_text())
            self.assertEqual((args.out / "check.txt").read_text(),
                             "output 05002000 00000140\n")


if __name__ == "__main__":
    unittest.main()
