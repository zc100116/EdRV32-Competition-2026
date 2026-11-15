#!/usr/bin/env python3
"""hagrid_to_yolo.py — card 83 step 8: sample HaGRIDv2 and write YOLO pose labels.

Uses the coordinator-approved 14 classes and source-class merges.
Clock domain: not applicable (offline dataset conversion).
"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path

import numpy as np


GROUPS = [
    ("palm", ("palm", "stop", "stop_inverted")),
    ("fist", ("fist",)),
    ("peace", ("peace", "peace_inverted", "two_up", "two_up_inverted")),
    ("point", ("one", "point")),
    ("grabbing", ("grabbing",)),
    ("grip", ("grip",)),
    ("thumb_index", ("thumb_index",)),
    ("ok", ("ok",)),
    ("like", ("like",)),
    ("dislike", ("dislike",)),
    ("three", ("three", "three2", "three3")),
    ("four", ("four",)),
    ("call", ("call",)),
    ("no_gesture", ("no_gesture",)),
]
CLASS_IDS = {source: i for i, (_, sources) in enumerate(GROUPS) for source in sources}


def convert(root):
    rng = np.random.default_rng(0)
    output = root / "yolo"
    statistics = []
    for split, limit in (("train", 8000), ("val", 800)):
        image_dir = output / "images" / split
        label_dir = output / "labels" / split
        image_dir.mkdir(parents=True, exist_ok=True)
        label_dir.mkdir(parents=True, exist_ok=True)
        image_counts = Counter()
        hand_counts = Counter()
        missing_counts = Counter()
        for name, sources in GROUPS:
            # Sample a merged category's complete image union, without source quotas.
            candidates = {}
            for source in sources:
                path = root / "annotations" / "annotations" / split / f"{source}.json"
                annotations = json.loads(path.read_text())
                for image_id, annotation in annotations.items():
                    candidates[image_id] = (source, annotation)
            image_ids = sorted(candidates)
            if name != "no_gesture":
                indices = rng.choice(len(image_ids), min(limit, len(image_ids)), replace=False)
                image_ids = [image_ids[int(index)] for index in indices]
            image_counts[name] = len(image_ids)
            for image_id in image_ids:
                source, annotation = candidates[image_id]
                lines = []
                for hand_index, label in enumerate(annotation["labels"]):
                    class_id = CLASS_IDS[label]
                    hand_name = GROUPS[class_id][0]
                    x, y, width, height = annotation["bboxes"][hand_index]
                    fields = [str(class_id)]
                    fields += [f"{value:.10f}" for value in
                               (x + width / 2, y + height / 2, width, height)]
                    landmarks = annotation["hand_landmarks"]
                    points = landmarks[hand_index] if landmarks else None
                    if not points:
                        fields += ["0", "0", "0"] * 21
                        missing_counts[hand_name] += 1
                    else:
                        if len(points) != 21:
                            raise ValueError(
                                f"{split}/{source}/{image_id}, hand {hand_index}: "
                                f"expected 21 landmarks, got {len(points)}"
                            )
                        for point_x, point_y in points:
                            fields += [f"{point_x:.10f}", f"{point_y:.10f}", "2"]
                    lines.append(" ".join(fields))
                    hand_counts[hand_name] += 1
                (label_dir / f"{image_id}.txt").write_text("\n".join(lines) + "\n")
                image = root / "HaGRIDv2_dataset_512" / source / f"{image_id}.jpg"
                # Dataset and extracted images share a filesystem; avoid duplicate image data.
                os.link(image, image_dir / image.name)
        statistics.append(f"{split}: class images hands hands_without_landmarks")
        for name, _ in GROUPS:
            statistics.append(
                f"{split} {name} {image_counts[name]} {hand_counts[name]} {missing_counts[name]}"
            )
        statistics.append(
            f"{split} TOTAL {sum(image_counts.values())} "
            f"{sum(hand_counts.values())} {sum(missing_counts.values())}"
        )
    config = Path(__file__).with_name("hagrid.yaml").read_text()
    (output / "hagrid.yaml").write_text(config)
    text = "\n".join(statistics) + "\n"
    (output / "data-stats.txt").write_text(text)
    print(text, end="")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="HaGRID directory under /root/edrv32")
    convert(parser.parse_args().root)
