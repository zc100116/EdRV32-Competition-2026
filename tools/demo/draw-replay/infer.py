#!/usr/bin/env python3
"""T-DRAW-FIX3: run the board's gesture/21-point INT8 model on HDMI frames.

Uses the existing descriptor reference and unchanged class-aware NMS thresholds.
Host/offline; input video and generated JSONL belong in build/draw-fix3/.
"""
import argparse
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/npu"))
import cv2
import numpy as np
import torch
from fixed_plan import build_plan
from models_eval import integer
from ref.npu_ref import Memory
from yolo_post_ref import make_heads


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--stop", type=int, default=1414)
    args = parser.parse_args()
    torch.set_num_threads(1)
    cv2.setNumThreads(1)
    plan = build_plan("gesture", 14, 63)
    snapshot = ROOT / "sw/apps/showcase/models/gesture"
    rows = json.loads((snapshot / "quantization.json").read_text())["convolutions"]
    memory = Memory()
    memory.load_hex(snapshot / "mem_model.hex")
    memory.load_hex(snapshot / "mem_desc.hex")
    registers = {key: int(value, 16) for key, value in
                 (line.split() for line in (snapshot / "regs.txt").read_text().splitlines())}
    heads = make_heads({"convolutions": rows})
    video = cv2.VideoCapture(str(args.video))
    fps = video.get(cv2.CAP_PROP_FPS)
    video.set(cv2.CAP_PROP_POS_FRAMES, args.start)
    started = time.monotonic()
    with args.output.open("w") as output:
        for frame in range(args.start, args.stop):
            ok, source = video.read()
            if not ok:
                raise RuntimeError(f"cannot read video frame {frame}")
            # Keep the HDMI toolbar/strokes: no reconstruction of obscured camera pixels.
            display = cv2.resize(source, (1280, 720))
            image = cv2.resize(display, (640, 360))
            image = cv2.copyMakeBorder(image, 12, 12, 0, 0, cv2.BORDER_CONSTANT,
                                      value=(114, 114, 114))
            rgb = np.ascontiguousarray(image[:, :, ::-1].transpose(2, 0, 1))
            tensor = torch.from_numpy(rgb)[None].float() / 255
            boxes, scores, classes, points = integer(memory, registers, plan, rows,
                                                     heads, tensor)
            boxes = (boxes - [0, 12, 0, 12]) * 2
            boxes[:, [0, 2]] = boxes[:, [0, 2]].clip(0, 1280)
            boxes[:, [1, 3]] = boxes[:, [1, 3]].clip(0, 720)
            points[:, :, :2] = (points[:, :, :2] - [0, 12]) * 2
            points[:, :, 0] = points[:, :, 0].clip(0, 1280)
            points[:, :, 1] = points[:, :, 1].clip(0, 720)
            hands = [dict(box=np.rint(b).astype(int).tolist(), score=round(float(s), 4),
                          cls=int(c), points=np.round(p, 3).tolist())
                     for b, s, c, p in zip(boxes, scores, classes, points)]
            output.write(json.dumps(dict(f=frame, ms=round(frame * 1000 / fps),
                                         hands=hands), separators=(",", ":")) + "\n")
            output.flush()
            if frame % 30 == 0:
                print(f"f={frame} hands={len(hands)} elapsed={time.monotonic()-started:.1f}",
                      flush=True)


if __name__ == "__main__":
    main()
