#!/usr/bin/env python3
# File: selftest.py
# Spec: npu-spec 2.6, 4.1, 4.4, 4.5, 5.6; npu-testplan TL-05/PP.
# Description: Hand-computed arithmetic, malformed candidate comparisons and stream checks.
# Clock domain: host.
"""Run without any RTL or simulator; deliberate faults must be rejected."""
import copy
import json
import struct
import unittest

from fixtures import BUILD, ROOT, fixture
from oracle import RECORD, check_image, compare, decode, distance, pack
from stream import Acceptance, beats


class PostTests(unittest.TestCase):
    def test_dfl_widths(self):
        table = [1 << 20] * 256
        den = 16 * (1 << 20)
        num = 120 * (1 << 20)
        self.assertEqual(den.bit_length(), 25)
        self.assertEqual(num.bit_length(), 27)
        self.assertEqual((num * 256 + den // 2).bit_length(), 35)
        self.assertEqual(distance([-128] * 16, table), 1920)
        table = [1 << 20] + [0] * 255
        for bin_index in (0, 1, 7, 15):
            bins = [-128] * 16
            bins[bin_index] = 127
            self.assertEqual(distance(bins, table), bin_index * 256)
        # Exact half-point: numerator=1, denominator=512 -> Q8 rounds 0.5 up to 1.
        table = [511, 1] + [0] * 254
        self.assertEqual(distance([0, -1] + [-128] * 14, table), 1)

    def test_layout_and_corruption(self):
        candidates = [[[-15360, -512, 655360, 400000], 1 << 24, 79, 5039]]
        payload = pack(candidates) + bytes(8)
        self.assertEqual(RECORD.size, 24)
        self.assertEqual(payload[20:24], struct.pack('<HH', 79, 5039))
        compare(payload, candidates, [5039])
        for byte in (0, 4, 8, 12, 16, 20, 22, 24):
            bad = bytearray(payload)
            bad[byte] ^= 1
            with self.assertRaises((AssertionError, KeyError)):
                compare(bad, candidates, [5039])
        rows = candidates + [[[-1, -2, 3, 4], 123, 0, 0]]
        with self.assertRaises(AssertionError):
            compare(pack(rows) + bytes(16), rows, [0, 5039])

    def test_threshold_ties_and_oracle(self):
        heads = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
        path = fixture(BUILD / 'post_selftest', count=12)
        raw = (path / 'raw.bin').read_bytes()
        candidates = decode(raw, heads, (103, 105, 103), 4194304)
        self.assertEqual(len(candidates), 12)
        self.assertTrue(all(row[2] == 0 for row in candidates))
        self.assertTrue(any(row[0][0] < 0 for row in candidates))
        compare((path / 'candidates.bin').read_bytes(), candidates, [row[3] for row in candidates])
        self.assertEqual(decode(raw, heads, (128,) * 3, 0), [])
        self.assertEqual(decode(raw, heads, (-128,) * 3, 1 << 24), [])
        # Change each table's best=127 probability to TH-1, TH, TH+1.
        for delta in (-1, 0, 1):
            for head in heads:
                head['probability_q24'][255] = 100 + delta
            result = decode(raw, heads, (127,) * 3, 100)
            self.assertEqual(len(result), 12 if delta == 1 else 0)
        # Independent existing public oracle agrees on the default complete candidate set.
        import sys
        sys.path.insert(0, str(ROOT))
        from tools.npu.yolo_post_ref import STAT_KEYS, decode_candidates
        original = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
        self.assertEqual(decode_candidates(raw, original, dict.fromkeys(STAT_KEYS, 0)), candidates)

    def test_full_capacity(self):
        path = fixture(BUILD / 'post_selftest_full', count=5040, pattern=1)
        rows = json.loads((path / 'candidates.json').read_text())
        self.assertEqual(len(rows), 5040)
        self.assertEqual(len((path / 'candidates.bin').read_bytes()), 120960)
        self.assertEqual([row[3] for row in rows], list(range(5040)))
        self.assertEqual({row[2] for row in rows}, set(range(80)))

    def test_tl05_decoder(self):
        heads = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
        words = [[0] * 16 for _ in range(62)]
        memory = {}
        for h, (width, height) in enumerate(((80, 48), (40, 24), (20, 12))):
            offset = 0x10000 + h * 2048
            # Probability 1 exercises bit24; 24-bit truncation must fail.
            heads[h]['probability_q24'][255] = 1 << 24
            data = struct.pack('<512I', *(heads[h]['exp_q20'] + heads[h]['probability_q24']))
            memory.update(enumerate(data, 0x100000 + offset))
            for kind in (1, 2):
                row = [0] * 16
                row[0] = 3 << 14 | (512 if kind == 2 else 0)
                row[3] = heads[h]['box_offset' if kind == 1 else 'class_offset']
                row[4] = width * height * 16
                row[9] = width | height << 16
                row[10] = (2 if kind == 1 else 3) << 8
                row[13:16] = [kind | h << 2, offset, 0]
                words.append(row)
        def read(address, size):
            return bytes(memory[address + i] for i in range(size))
        check_image(words, read, 0x100000, heads)
        for descriptor, word, value in ((0, 13, 1), (0, 14, 32), (62, 14, 1),
                                        (62, 15, 1), (62, 9, 0), (63, 13, 1)):
            bad = copy.deepcopy(words)
            bad[descriptor][word] = value
            with self.assertRaises(AssertionError):
                check_image(bad, read, 0x100000, heads)
        memory[0x100000 + 0x10000 + 1024 + 255 * 4 + 3] = 0
        with self.assertRaises(AssertionError):
            check_image(words, read, 0x100000, heads)

    def test_stream(self):
        stream = list(beats())
        self.assertEqual(len(stream), 12600)
        check = Acceptance()
        for cycle, beat in enumerate(stream):
            check.accept(cycle, beat)
            if beat[3] == 4:
                check.enqueue(beat[5])
                check.enqueue(beat[6])
        stats = check.finish(next(i for i, beat in enumerate(stream) if beat[3] == 4) + 12)
        self.assertEqual(stats['receive_us_200mhz'], 63)
        self.assertEqual(stats['pipeline_latency'], 12)
        bad = Acceptance()
        bad.accept(0, stream[0])
        with self.assertRaises(AssertionError):
            bad.accept(2, stream[1])
        check.enqueued.pop()
        with self.assertRaises(AssertionError):
            check.finish(12)


if __name__ == '__main__':
    unittest.main(verbosity=2)
