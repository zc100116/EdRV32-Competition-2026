#!/usr/bin/env python3
"""contact_sheets.py: card 86 step 6, deterministic dataset/class contact sheets.
Clock domain: not applicable (offline review images).
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import cv2
import numpy as np
from hand3d_gesture import NAMES


def sheets(root, output, dataset):
    rng = np.random.default_rng(0)
    groups = defaultdict(dict)
    for item in json.loads((root / 'records.json').read_text()):
        groups[item['class_id']][item['image']] = item
    output.mkdir(parents=True, exist_ok=True)
    for class_id, by_image in sorted(groups.items()):
        items = list(by_image.values())
        class_name = 'ignore_class' if class_id == 14 else NAMES[class_id]
        selected = rng.choice(len(items), min(24, len(items)), replace=False)
        canvas = np.full((6 * 300, 4 * 320, 3), 245, dtype='uint8')
        for cell, index in enumerate(selected):
            item = items[int(index)]
            image = cv2.imread(item['image'])
            box = np.array(item['box'])
            points = np.array(item['points'])
            # Crop around the labeled hand so fingertips remain readable in a sheet.
            low = np.maximum(0, np.floor(box[:2] - (box[2:] - box[:2]) * 0.3)).astype(int)
            high = np.minimum(image.shape[1::-1],
                              np.ceil(box[2:] + (box[2:] - box[:2]) * 0.3)).astype(int)
            cv2.rectangle(image, tuple(box[:2].astype(int)), tuple(box[2:].astype(int)),
                          (0, 255, 0), 2)
            for finger in range(5):
                chain = [0] + list(range(1 + finger * 4, 5 + finger * 4))
                for a, b in zip(chain[:-1], chain[1:]):
                    cv2.line(image, tuple(points[a].astype(int)), tuple(points[b].astype(int)),
                             (255, 100, 0), 1)
            for k, point in enumerate(points):
                xy = tuple(point.astype(int))
                cv2.circle(image, xy, 2, (0, 0, 255), -1)
                cv2.putText(image, str(k), xy, cv2.FONT_HERSHEY_SIMPLEX, 0.25, (0, 0, 0), 1)
            crop = image[low[1]:high[1], low[0]:high[0]]
            scale = min(310 / crop.shape[1], 260 / crop.shape[0])
            crop = cv2.resize(crop, None, fx=scale, fy=scale)
            x, y = (cell % 4) * 320, (cell // 4) * 300
            canvas[y:y+crop.shape[0], x:x+crop.shape[1]] = crop
            title = f"{cell+1} {class_name} {item['orientation']} {item['split']}"
            cv2.putText(canvas, title, (x + 3, y + 280), cv2.FONT_HERSHEY_SIMPLEX,
                        0.43, (0, 0, 0), 1)
        cv2.imwrite(str(output / f'{dataset}_{class_name}.jpg'), canvas)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('dataset')
    args = parser.parse_args()
    sheets(args.root, args.output, args.dataset)
