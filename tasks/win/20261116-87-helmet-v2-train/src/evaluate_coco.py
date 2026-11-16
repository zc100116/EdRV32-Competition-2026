"""evaluate_coco.py — T-HELMET-V2 step 5, local CPU comparison.

Reproduce the coordinator's 40 COCO person images and count detections.
Clock domain: not applicable.
"""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import random

from ultralytics import YOLO


def evaluate(weights, output):
    root = Path.home() / ".local/share/edrv32/npu"
    data = json.loads((root / "annotations/person_keypoints_val2017.json").read_text())
    people = defaultdict(list)
    for annotation in data["annotations"]:
        people[annotation["image_id"]].append(annotation)
    eligible = []
    for image in data["images"]:
        annotations = people[image["id"]]
        if (root / "val2017" / image["file_name"]).exists() and 1 <= len(annotations) <= 3:
            ratio = max(a["bbox"][3] for a in annotations) / image["height"]
            if 0.25 <= ratio <= 0.8:
                eligible.append(image)
    random.Random(0).shuffle(eligible)
    selected = eligible[:40]
    results = {"eligible_images": len(eligible), "images": len(selected),
               "persons": sum(len(people[i["id"]]) for i in selected),
               "imgsz": 640, "conf": 0.5, "iou": 0.7, "device": "cpu", "models": {}}
    for weight in weights:
        model = YOLO(weight)
        counts = {"helmet": 0, "head": 0}
        per_image = []
        paths = [str(root / "val2017" / image["file_name"]) for image in selected]
        predictions = (prediction for path in paths for prediction in model.predict(
            path, imgsz=640, conf=0.5, iou=0.7, device="cpu", verbose=False))
        for image, prediction in zip(selected, predictions):
            labels = prediction.boxes.cls.int().tolist()
            row = {"file": image["file_name"], "persons": len(people[image["id"]]),
                   "helmet": labels.count(0), "head": labels.count(1)}
            per_image.append(row)
            for name in counts:
                counts[name] += row[name]
        results["models"][str(weight)] = {**counts, "per_image": per_image}
    output.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("weights", nargs="+", type=Path)
    args = parser.parse_args()
    evaluate(args.weights, args.output)
