"""evaluate_server.py — T-HELMET-V2 step 5, original/new model comparison.

Measure Hard Hat per-class metrics and CrowdHuman head matching at IoU >= 0.5.
Clock domain: not applicable.
"""

import json
from pathlib import Path
import sys

import numpy as np
from ultralytics import YOLO


def match_count(predictions, heads):
    used = set()
    for prediction in predictions:
        left = np.maximum(prediction[:2], heads[:, :2])
        right = np.minimum(prediction[2:], heads[:, 2:])
        intersection = np.maximum(right - left, 0).prod(axis=1)
        union = ((prediction[2:] - prediction[:2]).prod()
                 + (heads[:, 2:] - heads[:, :2]).prod(axis=1) - intersection)
        overlaps = intersection / union
        for index in np.argsort(-overlaps):
            if overlaps[index] >= 0.5 and int(index) not in used:
                used.add(int(index))
                break
    return len(used)


root = Path(sys.argv[1])
report = {"crowdhuman_conf": 0.5, "match_iou": 0.5, "imgsz": 640, "models": {}}
weights = {"v1": root.parent / "runs/helmet-v8n/weights/best.pt",
           "v2": root / "train/weights/best.pt"}
for name, weight in weights.items():
    model = YOLO(weight)
    metrics = model.val(data=str(root.parent / "extra/helmet/yolo/helmet.yaml"),
                        imgsz=640, batch=128, workers=4, device=0, plots=False,
                        project=str(root / "evaluation"), name=f"hardhat-{name}")
    hardhat = {}
    for index, cls in enumerate(metrics.box.ap_class_index):
        hardhat[model.names[int(cls)]] = {
            "P": float(metrics.box.p[index]), "R": float(metrics.box.r[index]),
            "mAP50": float(metrics.box.ap50[index]),
            "mAP50_95": float(metrics.box.ap[index])}
    paths = sorted((root / "crowdhuman/images/val").glob("*.jpg"))
    totals = {"images": len(paths), "gt_heads": 0, "head_matches": 0,
              "helmet_matches": 0, "head_detections": 0, "helmet_detections": 0}
    per_image = []
    predictions = (prediction for offset in range(0, len(paths), 32)
                   for prediction in model.predict(
                       list(map(str, paths[offset:offset + 32])), imgsz=640, conf=0.5,
                       device=0, stream=True, verbose=False))
    for path, prediction in zip(paths, predictions):
        height, width = prediction.orig_shape
        labels = np.loadtxt(root / "crowdhuman/labels/val" / f"{path.stem}.txt",
                            ndmin=2)[:, 1:]
        centers = labels[:, :2] * [width, height]
        sizes = labels[:, 2:] * [width, height]
        heads = np.concatenate((centers - sizes / 2, centers + sizes / 2), axis=1)
        row = {"image": path.name, "gt_heads": len(heads)}
        for cls, class_name in ((0, "helmet"), (1, "head")):
            boxes = prediction.boxes.xyxy[prediction.boxes.cls == cls].cpu().numpy()
            row[f"{class_name}_detections"] = len(boxes)
            row[f"{class_name}_matches"] = match_count(boxes, heads)
        per_image.append(row)
        for key in row:
            if key != "image":
                totals[key] += row[key]
    totals["head_recall_iou50"] = totals["head_matches"] / totals["gt_heads"]
    totals["helmet_misclassification_per_gt"] = totals["helmet_matches"] / totals["gt_heads"]
    report["models"][name] = {"hardhat": hardhat, "crowdhuman": totals,
                              "crowdhuman_per_image": per_image}
    (root / "evaluation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(name, json.dumps({"hardhat": hardhat, "crowdhuman": totals}), flush=True)
