"""test_yolo_post.py — B2 software design 3.4; C11 host/reference checks.

Compile the board C sources, compare every EDDT field/order and operation count.
Clock domain: host; all generated artifacts live in build/npu/yolo_post.
"""
import ctypes as ct
import json
from pathlib import Path
import random
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/npu"))
import yolo_post_ref as reference

BUILD = ROOT / "build/npu/yolo_post"
OUTPUT_BYTES = 725760


class Detection(ct.Structure):
    _fields_ = [(name, ct.c_int16) for name in ("x0", "y0", "x1", "y1")] + [
        ("class_id", ct.c_uint16), ("score", ct.c_uint16)]


class Candidate(ct.Structure):
    _fields_ = [("xyxy_q8", ct.c_int32 * 4), ("probability_q24", ct.c_uint32),
                ("class_id", ct.c_uint16), ("anchor", ct.c_uint16)]


class Head(ct.Structure):
    _fields_ = [(name, ct.c_uint32) for name in ("box_offset", "class_offset", "plane_stride")]
    _fields_ += [(name, ct.c_uint16) for name in ("width", "height", "stride")]
    _fields_ += [(name, ct.c_int16) for name in ("class_threshold", "box_zero_point",
                                              "class_zero_point")]
    _fields_ += [("exp_q20", ct.c_uint32 * 256), ("probability_q24", ct.c_uint32 * 256)]


class Stats(ct.Structure):
    _fields_ = [(name, ct.c_uint32) for name in reference.STAT_KEYS]


class Surface(ct.Structure):
    _fields_ = [("pixels", ct.POINTER(ct.c_uint16)), ("stride", ct.c_uint32),
                ("width", ct.c_uint16), ("height", ct.c_uint16)]


def host_library():
    BUILD.mkdir(parents=True, exist_ok=True)
    library = BUILD / "libyolo.so"
    subprocess.run(["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-g",
                    "-fsanitize=undefined", "-fno-sanitize-recover=all", "-fPIC", "-shared",
                    *[str(ROOT / "sw/lib" / name) for name in
                      ("yolo_post.c", "yolo_tables.c", "draw.c")], "-o", str(library)], check=True)
    lib = ct.CDLL(str(library))
    lib.yolo_post_process.argtypes = [ct.POINTER(ct.c_int8), ct.POINTER(Head),
                                      ct.POINTER(Candidate), ct.POINTER(Detection),
                                      ct.POINTER(Stats)]
    lib.yolo_post_process.restype = ct.c_uint32
    coordinates = [ct.POINTER(Surface)] + [ct.c_int32] * 4 + [ct.c_uint16]
    lib.draw_fill.argtypes = coordinates
    lib.draw_rect.argtypes = coordinates
    lib.draw_text.argtypes = [ct.POINTER(Surface), ct.c_int32, ct.c_int32,
                              ct.c_char_p, ct.c_uint16]
    lib.draw_detection.argtypes = [ct.POINTER(Surface), ct.POINTER(Detection),
                                   ct.c_uint16, ct.c_uint16]
    return lib


def c_process(lib, output):
    buffer = (ct.c_int8 * len(output)).from_buffer_copy(output)
    heads = (Head * 3).in_dll(lib, "yolo_default_heads")
    workspace = (Candidate * 5040)()
    results = (Detection * 100)()
    stats = Stats()
    count = lib.yolo_post_process(buffer, heads, workspace, results, ct.byref(stats))
    rows = [tuple(getattr(row, name) for name, _ in Detection._fields_) for row in results[:count]]
    selected = [row.anchor for row in workspace[:stats.decoded_anchors]
                if row.probability_q24][:count]
    return rows, {name: getattr(stats, name) for name in reference.STAT_KEYS}, selected


def blank(heads):
    output = bytearray(OUTPUT_BYTES)
    for head in heads:
        start = head["class_offset"]
        output[start:start + 5 * head["plane_stride"]] = b"\x80" * (5 * head["plane_stride"])
    return output


def set_class(output, head, cell, channel, value):
    offset = head["class_offset"] + channel // 16 * head["plane_stride"] + cell * 16
    output[offset + channel % 16] = value & 255


def set_bins(output, head, cell, sides):
    for side, peak in enumerate(sides):
        start = head["box_offset"] + side * head["plane_stride"] + cell * 16
        output[start:start + 16] = bytes(127 if i == peak else 128 for i in range(16))


class YoloPostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lib = host_library()
        cls.heads = reference.load_heads()
        cls.log = []

    @classmethod
    def tearDownClass(cls):
        (BUILD / "host_stats.json").write_text(json.dumps(cls.log, indent=2) + "\n")

    def compare(self, name, output):
        expected, expected_stats = reference.postprocess(output, self.heads)
        actual, actual_stats, anchors = c_process(self.lib, output)
        self.assertEqual(actual, expected, name)
        self.assertEqual(actual_stats, expected_stats, name)
        self.log.append(dict(frame=name, count=len(actual), **actual_stats))
        return actual, anchors

    def test_empty_and_zero_decode(self):
        rows, _ = self.compare("empty", blank(self.heads))
        self.assertEqual(rows, [])
        self.assertEqual(self.log[-1]["decoded_anchors"], 0)
        self.assertEqual(self.log[-1]["class_comparisons"], 5040 * 81)

    def test_threshold_and_argmax_ties(self):
        for scale, head in enumerate(self.heads):
            with self.subTest(scale=scale):
                output = blank(self.heads)
                cell = 10 * head["width"] + 10
                set_class(output, head, cell, 79, head["class_threshold"] - 1)
                rows, _ = self.compare(f"below_threshold_{scale}", output)
                self.assertEqual(rows, [])
                set_class(output, head, cell, 79, head["class_threshold"])
                set_class(output, head, cell, 16, head["class_threshold"])
                rows, _ = self.compare(f"at_threshold_{scale}", output)
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0][4], 16)

    def test_nms_exact_iou_boundary(self):
        head = self.heads[0]
        cell = 20 * head["width"] + 20
        # Point distributions produce width=29 cells, height=2 cells.
        # dx=11: IoU=(29-11)/(29+11)=.45 exactly, hence both survive.
        for delta, expected in ((11, 2), (10, 1), (12, 2)):
            output = blank(self.heads)
            for position in (cell, cell + delta):
                set_class(output, head, position, 0, 127)
                set_bins(output, head, position, (14, 1, 15, 1))
            rows, anchors = self.compare(f"iou_delta_{delta}", output)
            self.assertEqual(len(rows), expected)
            self.assertEqual(anchors[0], cell)

    def test_class_aware_nms_and_score_order(self):
        head = self.heads[0]
        cell = 20 * head["width"] + 20
        output = blank(self.heads)
        set_class(output, head, cell, 79, 126)
        set_class(output, head, cell + 1, 0, 127)
        rows, anchors = self.compare("different_classes", output)
        self.assertEqual(len(rows), 2)
        self.assertEqual(anchors, [cell + 1, cell])
        set_class(output, head, cell, 0, 127)
        rows, anchors = self.compare("same_class_tie", output)
        self.assertEqual(len(rows), 1)
        self.assertEqual(anchors, [cell])

    def test_extreme_bins_transform_and_zero_area(self):
        for scale, head in enumerate(self.heads):
            output = blank(self.heads)
            cells = head["width"] * head["height"]
            for position in (0, cells - 1):
                set_class(output, head, position, 0, 127)
                set_bins(output, head, position, (15, 15, 15, 15))
            rows, _ = self.compare(f"clipping_{scale}", output)
            self.assertEqual(rows[0][:2], (0, 0))
            self.assertEqual(rows[-1][2:4], (1280, 720))
            for position in (0, cells - 1):
                set_bins(output, head, position, (0, 0, 0, 0))
            rows, _ = self.compare(f"zero_area_{scale}", output)
            self.assertEqual(len(rows), 2)
            for row in rows:
                self.assertEqual(row[:2], row[2:4])

    def test_dense_maximum_and_cap(self):
        output = bytearray(b"\x7f" * OUTPUT_BYTES)
        rows, _ = self.compare("all_max", output)
        self.assertEqual(len(rows), 100)
        self.assertEqual(self.log[-1]["decoded_anchors"], 5040)

    def test_random_full_and_sparse(self):
        for seed in range(5):
            rng = random.Random(seed)
            output = bytearray(rng.randbytes(OUTPUT_BYTES))
            self.compare(f"random_full_{seed}", output)
            sparse = blank(self.heads)
            for head in self.heads:
                start = head["box_offset"]
                sparse[start:head["class_offset"]] = output[start:head["class_offset"]]
                for _ in range(75):
                    set_class(sparse, head, rng.randrange(head["width"] * head["height"]),
                              rng.randrange(80), rng.randrange(head["class_threshold"], 128))
            self.compare(f"random_sparse_{seed}", sparse)

    def test_draw_fill_rect_stride_and_clipping(self):
        pixels = (ct.c_uint16 * (2 + 12 * 24))(*([0x1357] * (2 + 12 * 24)))
        surface = Surface(ct.cast(ct.byref(pixels, 2), ct.POINTER(ct.c_uint16)), 48, 20, 12)
        self.lib.draw_fill(ct.byref(surface), -3, -2, 6, 5, 0x1234)
        self.lib.draw_rect(ct.byref(surface), 10, 7, 25, 15, 0xabcd)
        for y in range(12):
            for x in range(24):
                expected = 0x1357
                if x < 6 and y < 5:
                    expected = 0x1234
                if x < 20 and ((10 <= x < 25 and y == 7) or (x == 10 and y >= 7)):
                    expected = 0xabcd
                self.assertEqual(pixels[1 + y * 24 + x], expected, (x, y))
        self.assertEqual(pixels[0], 0x1357)
        self.assertEqual(pixels[-1], 0x1357)
        before = bytes(pixels)
        self.lib.draw_rect(ct.byref(surface), 10, 7, 10, 9, 0xffff)
        self.lib.draw_rect(ct.byref(surface), 10, 7, 15, 7, 0xffff)
        self.assertEqual(bytes(pixels), before)

    def test_draw_text_ascii_and_detection_labels(self):
        pixels = (ct.c_uint16 * (256 * 48))()
        surface = Surface(pixels, 512, 256, 48)
        self.lib.draw_text(ct.byref(surface), 0, 0, b" ", 0xffff)
        self.assertFalse(any(pixels))
        self.lib.draw_text(ct.byref(surface), 0, 0, b"A", 0xffff)
        glyph = [sum((pixels[y * 256 + x] != 0) << (7 - x) for x in range(8))
                 for y in range(16)]
        self.assertEqual(glyph, [0, 0, 0, 0, 24, 36, 36, 66, 66, 126, 66, 66, 66, 66, 0, 0])
        for code in range(32, 127):
            self.lib.draw_text(ct.byref(surface), -4, 40, bytes([code]), 0xffff)
        for class_id in range(80):
            for score in (250, 875, 1000):
                detection = Detection(4, 20, 64, 44, class_id, score)
                self.lib.draw_detection(ct.byref(surface), ct.byref(detection), 0x07e0, 0xffff)
                self.assertEqual(pixels[20 * 256 + 4], 0x07e0)
        # A label must render exactly the specified class name and decimal confidence.
        actual = (ct.c_uint16 * (256 * 48))()
        expected = (ct.c_uint16 * (256 * 48))()
        a = Surface(actual, 512, 256, 48)
        b = Surface(expected, 512, 256, 48)
        detection = Detection(2, 20, 240, 46, 0, 875)
        self.lib.draw_detection(ct.byref(a), ct.byref(detection), 0x07e0, 0xffff)
        self.lib.draw_rect(ct.byref(b), 2, 20, 240, 46, 0x07e0)
        self.lib.draw_fill(ct.byref(b), 2, 4, 2 + 12 * 8, 20, 0x07e0)
        self.lib.draw_text(ct.byref(b), 2, 4, b"person 0.875", 0xffff)
        self.assertEqual(bytes(actual), bytes(expected))
        top = Detection(250, 0, 256, 12, 0, 1000)
        self.lib.draw_detection(ct.byref(a), ct.byref(top), 0x07e0, 0xffff)
        self.assertEqual(actual[250], 0x07e0)


if __name__ == "__main__":
    unittest.main()
