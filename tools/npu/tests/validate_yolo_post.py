#!/usr/bin/env python3
"""validate_yolo_post.py — B2 software design 3.4: real OUTPUT/float comparison.

Run compile_yolo + NPU reference on three COCO images; compare C/Python exactly.
Float differences are observations, never acceptance criteria. Clock domain: host.
"""
import json
from pathlib import Path
import random
import subprocess
import sys

import numpy as np
import torch
from ultralytics.nn.modules.block import DFL
from ultralytics.utils.nms import non_max_suppression
from ultralytics.utils.tal import dist2bbox

from test_yolo_post import BUILD, ROOT, blank, c_process, host_library, set_class
import yolo_post_ref as reference
from ref import npu_ref

DATA = Path.home() / ".local/share/edrv32/npu/coco128/images/train2017"


def floating_detections(output, heads, quantization):
    rows = {row["name"]: row for row in quantization["convolutions"]}
    raw = np.frombuffer(output, dtype=np.int8)
    boxes = []
    classes = []
    dfl = DFL(16).eval()
    with torch.inference_mode():
        for scale, head in enumerate(heads):
            cells = head["width"] * head["height"]

            def tensor(branch, channels):
                offset = head["box_offset" if branch == "box" else "class_offset"]
                physical = raw[offset:offset + channels * cells]
                logical = physical.reshape(channels // 16, cells, 16).transpose(0, 2, 1)
                value = torch.from_numpy(logical.reshape(1, channels, cells).copy()).float()
                row = rows[f"D{scale}.{branch}.out"]
                return (value - row["output_zero_point"]) * row["output_scale"]

            yy, xx = torch.meshgrid(torch.arange(head["height"]), torch.arange(head["width"]),
                                    indexing="ij")
            anchors = torch.stack((xx.flatten(), yy.flatten())).float() + .5
            boxes.append(dist2bbox(dfl(tensor("box", 64)), anchors, xywh=True, dim=1) *
                         head["stride"])
            classes.append(tensor("cls", 80).sigmoid())
        prediction = torch.cat((torch.cat(boxes, 2), torch.cat(classes, 2)), 1)
        # Explicit nc=80 and class-aware defaults; indices identify the same raw anchor.
        detections, indices = non_max_suppression(prediction, .25, .45, max_det=100,
                                                 nc=80, return_idxs=True, max_time_img=60)
    rows = detections[0].tolist()
    for row in rows:
        row[0] = max(0, min(1280, row[0] * 2))
        row[1] = max(0, min(720, (row[1] - 12) * 2))
        row[2] = max(0, min(1280, row[2] * 2))
        row[3] = max(0, min(720, (row[3] - 12) * 2))
    return rows, [int(i) for i in indices[0]]


def compare(name, output, lib, heads, quantization):
    expected, stats = reference.postprocess(output, heads)
    actual, c_stats, fixed_anchors = c_process(lib, output)
    assert actual == expected, f"{name}: C/Python EDDT mismatch"
    assert c_stats == stats, f"{name}: C/Python operation count mismatch"
    assert reference.run(output, quantization) == actual, f"{name}: public run API mismatch"
    float_rows, float_anchors = floating_detections(output, heads, quantization)
    floating = {anchor: row for anchor, row in zip(float_anchors, float_rows)}
    coordinate_errors = []
    score_errors = []
    matched = 0
    for anchor, fixed in zip(fixed_anchors, actual):
        if anchor in floating and int(floating[anchor][5]) == fixed[4]:
            matched += 1
            coordinate_errors.extend(abs(fixed[i] - floating[anchor][i]) for i in range(4))
            score_errors.append(abs(fixed[5] - floating[anchor][4] * 1000))
    result = dict(frame=name, c_python="PASS", fixed_count=len(actual), float_count=len(float_rows),
                  count_delta=len(actual) - len(float_rows), matched_anchor_class=matched,
                  fixed_unmatched=len(actual) - matched, float_unmatched=len(float_rows) - matched,
                  max_coordinate_error_display_px=max(coordinate_errors, default=0),
                  max_score_error_permil=max(score_errors, default=0), stats=stats)
    print(json.dumps(result), flush=True)
    return result


def main():
    torch.set_num_threads(1)
    lib = host_library()
    heads = reference.load_heads()
    quantization = json.loads((ROOT / "build/npu/quantized/quantization.json").read_text())
    results = []
    for number in (9, 529, 650):
        case = BUILD / f"{number:06d}"
        image = DATA / f"{number:012d}.jpg"
        subprocess.run([sys.executable, str(ROOT / "tools/npu/compile_yolo.py"),
                        "--image", str(image), "--out", str(case)], check=True)
        memory = npu_ref.run_case(case)
        output = memory.read(0x05000000, 725760)
        (case / "output.bin").write_bytes(output)
        results.append(compare(image.name, output, lib, heads, quantization))
    # Synthetic physical OUTPUT frames supplement the real model outputs.
    for seed in range(3):
        rng = random.Random(seed)
        output = bytearray(rng.randbytes(725760))
        results.append(compare(f"random_full_{seed}", output, lib, heads, quantization))
        sparse = blank(heads)
        for head in heads:
            start = head["box_offset"]
            sparse[start:head["class_offset"]] = output[start:head["class_offset"]]
            for _ in range(75):
                set_class(sparse, head, rng.randrange(head["width"] * head["height"]),
                          rng.randrange(80), rng.randrange(head["class_threshold"], 128))
        results.append(compare(f"random_sparse_{seed}", sparse, lib, heads, quantization))
    (BUILD / "float_comparison.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"PASS: {len(results)} C/Python frames; float differences recorded only", flush=True)


if __name__ == "__main__":
    main()
