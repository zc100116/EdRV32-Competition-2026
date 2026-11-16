"""crowdhuman_heads.py — T-HELMET-V2 step 2, CrowdHuman hbox conversion.

Reject whole images under the task's contamination rules, filter with v1,
and sample head-only YOLO labels. Clock domain: not applicable.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from ultralytics import YOLO


def annotation_reasons(boxes):
    """Official ODGT attributes are optional; absent ignore means not ignored."""
    return {
        "extra_ignore": any(b.get("extra", {}).get("ignore", 0) == 1 for b in boxes),
        "head_ignore": any(b.get("head_attr", {}).get("ignore", 0) == 1 for b in boxes),
        "mask": any(b["tag"] == "mask" for b in boxes),
        "over_15_heads": sum(b["tag"] == "person" for b in boxes) > 15,
    }


def helmet_overlap(helmets, heads):
    for helmet in helmets:
        left = np.maximum(helmet[:2], heads[:, :2])
        right = np.minimum(helmet[2:], heads[:, 2:])
        intersection = np.maximum(right - left, 0).prod(axis=1)
        union = ((helmet[2:] - helmet[:2]).prod()
                 + (heads[:, 2:] - heads[:, :2]).prod(axis=1) - intersection)
        if np.any(intersection / union >= 0.3):
            return True
    return False


def convert(root):
    model = YOLO(root.parent / "runs/helmet-v8n/weights/best.pt")
    rng = np.random.default_rng(0)
    all_stats = {}
    for split in ("train", "val"):
        records = [json.loads(line) for line in
                   (root / "raw" / f"annotation_{split}.odgt").read_text().splitlines()]
        rules = ["extra_ignore", "head_ignore", "mask", "over_15_heads", "small_head"]
        stats = {"input_images": len(records),
                 "rule_matches": dict.fromkeys(rules, 0),
                 "first_rejection": dict.fromkeys(rules + ["helmet_overlap"], 0)}
        candidates = []
        for record in records:
            boxes = record["gtboxes"]
            reasons = annotation_reasons(boxes)
            image_path = root / "raw" / "Images" / f'{record["ID"]}.jpg'
            with Image.open(image_path) as image:
                width, height = image.size
            heads = [b["hbox"] for b in boxes if b["tag"] == "person"]
            reasons["small_head"] = any(
                max(b[2:]) * 640 / max(width, height) < 8 for b in heads)
            for rule in rules:
                stats["rule_matches"][rule] += int(reasons[rule])
            rejected = next((rule for rule in rules if reasons[rule]), None)
            if rejected:
                stats["first_rejection"][rejected] += 1
                continue
            candidates.append((record["ID"], width, height, heads))
        stats["before_helmet_filter"] = len(candidates)
        accepted = []
        paths = [str(root / "raw" / "Images" / f"{item[0]}.jpg") for item in candidates]
        predictions = (prediction for offset in range(0, len(paths), 32)
                       for prediction in model.predict(
                           paths[offset:offset + 32], imgsz=640, conf=0.5, classes=[0],
                           device=0, stream=True, verbose=False))
        for item, prediction in zip(candidates, predictions):
            heads = np.array(item[3], dtype=float).reshape(-1, 4)
            heads[:, 2:] += heads[:, :2]
            if helmet_overlap(prediction.boxes.xyxy.cpu().numpy(), heads):
                stats["first_rejection"]["helmet_overlap"] += 1
            else:
                accepted.append(item)
        stats["eligible_images"] = len(accepted)
        all_stats[split] = stats
        (root / "filter-stats.json").write_text(json.dumps(all_stats, indent=2) + "\n")
        print(json.dumps({split: stats}), flush=True)
        # Coordinator approved all eligible training images and at most 600 val images.
        count = len(accepted) if split == "train" else min(600, len(accepted))
        selected = (np.arange(count) if split == "train"
                    else rng.choice(len(accepted), count, replace=False))
        image_dir = root / "crowdhuman/images" / split
        label_dir = root / "crowdhuman/labels" / split
        image_dir.mkdir(parents=True, exist_ok=True)
        label_dir.mkdir(parents=True, exist_ok=True)
        for index in selected:
            name, width, height, heads = accepted[index]
            (image_dir / f"{name}.jpg").symlink_to(root / "raw/Images" / f"{name}.jpg")
            labels = []
            for x, y, w, h in heads:
                labels.append(f"1 {(x+w/2)/width:.8f} {(y+h/2)/height:.8f} "
                              f"{w/width:.8f} {h/height:.8f}")
            (label_dir / f"{name}.txt").write_text("\n".join(labels) + "\n")
        stats["sampled_images"] = count
        stats["sampled_heads"] = sum(len(accepted[i][3]) for i in selected)
        (root / "filter-stats.json").write_text(json.dumps(all_stats, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    convert(parser.parse_args().root)
