#!/usr/bin/env python3
"""T-HAND-BOARD: board C post/decode vs hand_eval INT8 on two sampled val images.

Use the offline evaluation's seeded sample and A letterbox; host clock.
"""
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/npu"))
import cv2
import numpy as np
import torch
from compile_yolo import read_model_hex
from fixed_plan import build_plan, descriptors
from format import BASES
from hand_data import selected, letterbox
from hand_eval import int8
from pose_eval import integer_keep, output_bytes
from ref.npu_ref import Memory
from yolo_post_ref import make_heads, decode_candidates, postprocess


def main():
    torch.set_num_threads(1)
    out = ROOT / "build/npu/hand_board/test"
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / "sw/apps/showcase/models/yolov8n-hand"
    quant = json.loads((source / "quantization.json").read_text())
    plan = build_plan("hand")
    encoded = descriptors(plan, quant["convolutions"])
    memory = Memory()
    memory.write(BASES["MODEL_BASE"], read_model_hex(source / "mem_model.hex", BASES["MODEL_BASE"]))
    memory.write(BASES["DESC_BASE"], b"".join(d.encode() for d in encoded))
    registers = BASES | {"DESC_COUNT": len(encoded)}
    heads = make_heads(quant)
    rows, _ = selected("val", 300)
    for row in rows[:2]:
        image, _, _ = letterbox(cv2.imread(str(row["path"])), row["boxes"], row["points"])
        boxes, _, points = int8(memory, registers, plan, quant["convolutions"], heads, image)
        points[:, :, 0] = np.clip(points[:, :, 0] * 2, 0, 1280)
        points[:, :, 1] = np.clip((points[:, :, 1] - 12) * 2, 0, 720)
        raw = memory.read(BASES["OUTPUT_BASE"], output_bytes(plan))
        stem = row["path"].stem
        raw_path = out / f"{stem}.output"
        raw_path.write_bytes(raw)
        kept = integer_keep(decode_candidates(raw, heads))
        mapped, _ = postprocess(raw, heads)
        assert len(kept) > 0
        expected = bytearray(struct.pack("<I", len(kept)))
        for i, (candidate, detection) in enumerate(zip(kept, mapped)):
            mapped_box = np.clip((boxes[i] - [0, 12, 0, 12]) * 2,
                                 0, [1280, 720, 1280, 720])
            assert max(abs(mapped_box - detection[:4])) <= .5
            expected.extend(struct.pack("<H6H", candidate[3], *detection))
            expected.extend(struct.pack("<63f", *points[i].flatten()))
        expected_path = out / f"{stem}.expected"
        expected_path.write_bytes(expected)
        subprocess.run([sys.argv[1], raw_path, expected_path], check=True)


if __name__ == "__main__":
    main()
