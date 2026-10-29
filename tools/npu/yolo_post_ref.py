#!/usr/bin/env python3
"""yolo_post_ref.py — npu-spec 2.2; B2 software design 3.4/3.5a.

Standard-library integer reference; contract: sw/lib/README.md.
Clock domain: host. Input is the 725760-byte physical C16 OUTPUT buffer.
"""
import argparse
import json
import math
from pathlib import Path
import struct

TABLES = Path(__file__).resolve().parents[2] / "sw/lib/yolo_tables.json"
STAT_KEYS = ("class_comparisons", "decoded_anchors", "dfl_bin_comparisons", "exp_lookups",
             "sort_comparisons", "nms_class_comparisons", "iou_comparisons")


def make_heads(quantization):
    """Construct the offline LUTs shared by the C generator and public run API."""
    rows = {row["name"]: row for row in quantization["convolutions"]}
    heads = []
    offset = 0
    # fixed_plan.build_plan(): each scale is contiguous box C64, then class C80.
    for scale, (width, height, stride) in enumerate(((80, 48, 8), (40, 24, 16),
                                                   (20, 12, 32))):
        box = rows[f"D{scale}.box.out"]
        classes = rows[f"D{scale}.cls.out"]
        plane_stride = width * height * 16
        logits = [(q - classes["output_zero_point"]) * classes["output_scale"]
                  for q in range(-128, 128)]
        threshold = next((q for q, logit in zip(range(-128, 128), logits)
                          if logit > math.log(1 / 3)), 128)
        heads.append(dict(
            box_offset=offset, class_offset=offset + plane_stride * 4,
            plane_stride=plane_stride, width=width, height=height, stride=stride,
            class_threshold=threshold, box_zero_point=box["output_zero_point"],
            class_zero_point=classes["output_zero_point"],
            exp_q20=[math.floor(math.exp(-delta * box["output_scale"]) * (1 << 20) + .5)
                     for delta in range(256)],
            probability_q24=[math.floor((1 << 24) / (1 + math.exp(-logit)) + .5)
                             for logit in logits]))
        offset += plane_stride * 9
    return heads


def load_heads(path=TABLES):
    return json.loads(Path(path).read_text())


def decode_candidates(output, heads, stats):
    raw = memoryview(output).cast("b")
    candidates = []
    anchor_base = 0
    for head in heads:
        plane_stride = head["plane_stride"]
        for cell in range(head["width"] * head["height"]):
            best = -129
            class_id = 0
            for channel in range(80):
                value = raw[head["class_offset"] + (channel // 16) * plane_stride +
                            cell * 16 + channel % 16]
                if value > best:
                    best, class_id = value, channel
            stats["class_comparisons"] += 81
            if best < head["class_threshold"]:
                continue
            xyxy = []
            for side in range(4):
                start = head["box_offset"] + side * plane_stride + cell * 16
                bins = raw[start:start + 16]
                peak = max(bins)
                weights = [head["exp_q20"][peak - value] for value in bins]
                denominator = sum(weights)
                numerator = sum(i * weight for i, weight in enumerate(weights))
                distance = (numerator * 256 + denominator // 2) // denominator
                center = (cell // head["width"] if side & 1 else cell % head["width"])
                xyxy.append((center * 256 + 128 + (-distance if side < 2 else distance)) *
                            head["stride"])
            stats["decoded_anchors"] += 1
            stats["dfl_bin_comparisons"] += 60
            stats["exp_lookups"] += 64
            candidates.append([xyxy, head["probability_q24"][best + 128],
                               class_id, anchor_base + cell])
        anchor_base += head["width"] * head["height"]
    return candidates


def integer_sort(items, stats):
    """Use C's heap comparison sequence so operation counts also agree exactly."""
    def better(a, b):
        stats["sort_comparisons"] += 1
        return a[1] > b[1] if a[1] != b[1] else a[3] < b[3]

    def sift(count, root):
        while 2 * root + 1 < count:
            child = 2 * root + 1
            if child + 1 < count and better(items[child], items[child + 1]):
                child += 1
            if not better(items[root], items[child]):
                break
            items[root], items[child] = items[child], items[root]
            root = child

    for root in range(len(items) // 2 - 1, -1, -1):
        sift(len(items), root)
    for end in range(len(items) - 1, 0, -1):
        items[0], items[end] = items[end], items[0]
        sift(end, 0)


def suppresses(a, b):
    width = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    height = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    intersection = width * height
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    return intersection * 20 > (area_a + area_b - intersection) * 9


def postprocess(output, heads):
    """Return (EDDT tuples x0,y0,x1,y1,class,score, statistics), in score order."""
    stats = dict.fromkeys(STAT_KEYS, 0)
    candidates = decode_candidates(output, heads, stats)
    integer_sort(candidates, stats)
    detections = []
    for i, candidate in enumerate(candidates):
        if len(detections) == 100:
            break
        box, probability, class_id, _ = candidate
        if probability == 0:
            continue
        mapped = [(max(0, min((value - padding * 256) * 2, limit * 256)) + 128) // 256
                  for value, padding, limit in zip(box, (0, 12, 0, 12),
                                                   (1280, 720, 1280, 720))]
        detections.append(tuple(mapped + [class_id, (probability * 1000 + (1 << 23)) >> 24]))
        for other in candidates[i + 1:]:
            if other[1] == 0:
                continue
            stats["nms_class_comparisons"] += 1
            if other[2] == class_id:
                stats["iou_comparisons"] += 1
                if suppresses(box, other[0]):
                    other[1] = 0
    return detections, stats


def run(output_bytes, quant_params):
    """Debug-tool API: raw OUTPUT + unmodified quantization.json dict -> EDDT tuples.

    Construct tables offline with standard-library math, exactly as the C generator;
    all filtering, DFL, NMS and output conversion thereafter use integers only.
    """
    return postprocess(output_bytes, make_heads(quant_params))[0]


def pack_detections(detections):
    """Little-endian EDDT entries; caller supplies the 16-byte frame header."""
    return b"".join(struct.pack("<hhhhHH", *row) for row in detections)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--tables", type=Path, default=TABLES)
    args = parser.parse_args()
    detections, stats = postprocess(args.output.read_bytes(), load_heads(args.tables))
    print(json.dumps(dict(detections=detections, stats=stats), indent=2))


if __name__ == "__main__":
    main()
