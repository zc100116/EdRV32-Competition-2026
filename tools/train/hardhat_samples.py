#!/usr/bin/env python3
# hardhat_samples.py — T-HELMET-DATA sample visualization.
# Draw six PNG examples using the project's existing OpenCV environment.
# Clock domain: not applicable (host tool).

from pathlib import Path

import cv2


def main():
    root = Path(__file__).resolve().parents[2] / "build/helmet"
    output = root / "samples"
    output.mkdir(parents=True, exist_ok=True)
    for split in ("train", "val"):
        for path in sorted((root / "yolo/images" / split).glob("*.png"))[:3]:
            image = cv2.imread(str(path))
            height, width = image.shape[:2]
            labels = root / "yolo/labels" / split / f"{path.stem}.txt"
            for line in labels.read_text().splitlines():
                category, x, y, w, h = map(float, line.split())
                category = int(category)
                left = round((x - w / 2) * width)
                top = round((y - h / 2) * height)
                right = round((x + w / 2) * width)
                bottom = round((y + h / 2) * height)
                color = ((0, 220, 0), (0, 0, 255))[category]
                cv2.rectangle(image, (left, top), (right, bottom), color, 2)
                cv2.putText(
                    image, ("helmet", "head")[category], (left, max(12, top - 3)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1,
                )
            destination = output / f"{split}-{path.name}"
            if not cv2.imwrite(str(destination), image):
                raise OSError(f"Failed to write sample: {destination}")
            print(destination)


if __name__ == "__main__":
    main()
