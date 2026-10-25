"""Evaluate a candidate INT8 image against held-out COCO128 labels.

This measures host-emulated packed arithmetic, not FPGA throughput or a
certified COCO validation result. Both float and INT8 paths use the same fixed
640x384 input preprocessing and the same NMS settings.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import torch
from ultralytics import YOLO
from ultralytics.utils.metrics import ap_per_class, box_iou

from yolo_v8n_quantize import DEFAULT_WEIGHTS
from yolo_v8n_validate_quant import check


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CANDIDATE = ROOT / "out/models/yolov8n_int8_coco96.bin"
DEFAULT_DATASET = ROOT / "out/calibration/coco128"


def labels_for(image: Path, dataset: Path) -> tuple[np.ndarray, np.ndarray]:
    label_path = dataset / "labels/train2017" / f"{image.stem}.txt"
    if not label_path.exists():
        return np.empty(0, dtype=np.int64), np.empty((0, 4), dtype=np.float32)
    labels = np.loadtxt(label_path, ndmin=2, dtype=np.float32)
    original = cv2.imread(str(image), cv2.IMREAD_COLOR)
    height, width = original.shape[:2]
    ratio = min(640.0 / width, 384.0 / height)
    scaled_width, scaled_height = round(width * ratio), round(height * ratio)
    sx, sy = scaled_width / width, scaled_height / height
    left, top = (640 - scaled_width) // 2, (384 - scaled_height) // 2
    xc, yc, bw, bh = (labels[:, index] for index in range(1, 5))
    boxes = np.stack(((xc - bw / 2) * width * sx + left,
                      (yc - bh / 2) * height * sy + top,
                      (xc + bw / 2) * width * sx + left,
                      (yc + bh / 2) * height * sy + top), axis=1)
    return labels[:, 0].astype(np.int64), boxes.astype(np.float32)


def accumulate(predictions: list[dict], classes: np.ndarray,
               boxes: np.ndarray, statistics: dict) -> None:
    pred_classes = np.array([row["class"] for row in predictions],
                            dtype=np.int64)
    confidences = np.array([row["confidence"] for row in predictions],
                           dtype=np.float32)
    pred_boxes = np.array([row["xyxy"] for row in predictions],
                          dtype=np.float32).reshape(-1, 4)
    correct = np.zeros((len(predictions), 10), dtype=bool)
    if len(predictions) and len(classes):
        overlap = box_iou(torch.from_numpy(pred_boxes),
                          torch.from_numpy(boxes)).numpy()
        thresholds = np.linspace(0.5, 0.95, 10)
        for column, threshold in enumerate(thresholds):
            claimed = set()
            for pred_index in range(len(predictions)):
                possible = np.where((classes == pred_classes[pred_index]) &
                                    (overlap[pred_index] >= threshold))[0]
                possible = [item for item in possible if item not in claimed]
                if possible:
                    match = max(possible, key=lambda item: overlap[pred_index, item])
                    claimed.add(match)
                    correct[pred_index, column] = True
    statistics["tp"].append(correct)
    statistics["conf"].append(confidences)
    statistics["pred_cls"].append(pred_classes)
    statistics["target_cls"].append(classes)


def summarize(statistics: dict) -> dict:
    tp = np.concatenate(statistics["tp"], axis=0)
    confidence = np.concatenate(statistics["conf"])
    predicted = np.concatenate(statistics["pred_cls"])
    target = np.concatenate(statistics["target_cls"])
    if not len(target):
        raise ValueError("held-out split has no labels")
    average_precision = ap_per_class(tp, confidence, predicted, target)[5]
    return {
        "images": len(statistics["tp"]),
        "labels": len(target),
        "predictions": len(predicted),
        "classes_with_labels": int(len(np.unique(target))),
        "map50": float(average_precision[:, 0].mean()),
        "map50_95": float(average_precision.mean()),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, default=DEFAULT_CANDIDATE)
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--calibration-count", type=int, default=96)
    parser.add_argument("--limit", type=int, default=32)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    images = sorted((args.dataset / "images/train2017").glob("*.jpg"))
    held_out = images[args.calibration_count:
                      args.calibration_count + args.limit]
    if not held_out:
        parser.error("no held-out images")
    network = YOLO(str(args.weights)).model.eval().fuse(verbose=False)
    statistics = {branch: {key: [] for key in
                  ("tp", "conf", "pred_cls", "target_cls")}
                  for branch in ("float", "int8")}
    layer_mae = []
    candidate_counts = []
    for index, image in enumerate(held_out, 1):
        result = check(args.weights, args.candidate, image,
                       network=network, all_detections=True)
        classes, boxes = labels_for(image, args.dataset)
        accumulate(result["float_detections"], classes, boxes,
                   statistics["float"])
        accumulate(result["quant_detections"], classes, boxes,
                   statistics["int8"])
        layer_mae.append(result["score_mae"])
        candidate_counts.append(result["quant_candidates_at_025"])
        if index % 8 == 0 or index == len(held_out):
            print(f"evaluated {index}/{len(held_out)} images")
    report = {
        "split": "COCO128 sorted images after calibration set",
        "calibration_count": args.calibration_count,
        "held_out_images": [str(path.resolve()) for path in held_out],
        "candidate": str(args.candidate.resolve()),
        "nms_confidence": 0.001,
        "nms_iou": 0.7,
        "float": summarize(statistics["float"]),
        "int8": summarize(statistics["int8"]),
        "mean_score_mae": float(np.mean(layer_mae)),
        "max_candidates_at_025": max(candidate_counts),
        "mean_candidates_at_025": float(np.mean(candidate_counts)),
    }
    output = args.output or args.candidate.with_name(
        args.candidate.stem + "_eval.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"float: {report['float']}")
    print(f"INT8:  {report['int8']}")
    print(f"report: {output.resolve()}")


if __name__ == "__main__":
    main()
