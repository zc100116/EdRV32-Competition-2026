#!/usr/bin/env python3
# hardhat_to_yolo.py — T-HELMET-DATA, coordinator-approved FiftyOne mirror.
# Convert Hard Hat Workers annotations to two-class YOLO and package the dataset.
# Clock domain: not applicable (host tool); Python standard library only.

import argparse
from collections import Counter
import json
from pathlib import Path
import random
import shutil
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source", type=Path, nargs="?",
        default=Path.home() / ".local/share/edrv32/hardhat",
    )
    source = parser.parse_args().source
    samples = json.loads((source / "samples.json").read_text())["samples"]
    samples.sort(key=lambda sample: sample["filepath"])
    random.Random(0).shuffle(samples)
    cut = len(samples) * 9 // 10
    output = Path(__file__).resolve().parents[2] / "build/helmet/yolo"
    classes = {"helmet": 0, "head": 1}
    for split, subset in (("train", samples[:cut]), ("val", samples[cut:])):
        images = output / "images" / split
        labels = output / "labels" / split
        images.mkdir(parents=True, exist_ok=True)
        labels.mkdir(parents=True, exist_ok=True)
        counts = Counter()
        discarded = 0
        for sample in subset:
            image = source / sample["filepath"]
            shutil.copyfile(image, images / image.name)
            lines = []
            for detection in sample["ground_truth"]["detections"]:
                name = detection["label"]
                if name == "person":
                    discarded += 1
                    continue
                category = classes[name]
                x, y, width, height = detection["bounding_box"]
                lines.append(
                    f"{category} {x + width / 2:.10f} {y + height / 2:.10f} "
                    f"{width:.10f} {height:.10f}\n"
                )
                counts[name] += 1
            (labels / f"{image.stem}.txt").write_text("".join(lines))
        print(
            f"{split}: images={len(subset)} helmet={counts['helmet']} "
            f"head={counts['head']} discarded_person={discarded}"
        )
    # Omitting path makes Ultralytics resolve these paths relative to helmet.yaml.
    (output / "helmet.yaml").write_text(
        "train: images/train\nval: images/val\nnames:\n  0: helmet\n  1: head\n"
    )
    archive = output.parent / "helmet-yolo.tar"
    with tarfile.open(archive, "w") as tar:
        tar.add(output, arcname="yolo")
    print(f"archive: {archive} ({archive.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
