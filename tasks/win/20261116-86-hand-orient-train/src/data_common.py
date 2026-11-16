#!/usr/bin/env python3
"""data_common.py: card 86 steps 3a/4/5, shared box and YOLO geometry.
Clock domain: not applicable (offline conversion).
"""
import json
from pathlib import Path
from PIL import Image
import numpy as np


def hand_box(points, margins):
    low = points.min(axis=0)
    high = points.max(axis=0)
    long_edge = (high - low).max()
    return np.r_[low - np.asarray(margins[:2]) * long_edge,
                 high + np.asarray(margins[2:]) * long_edge]


def outside(points, width, height):
    return bool(np.any(points < 0) or np.any(points >= [width, height]))


def iou(box, boxes):
    boxes = np.asarray(boxes).reshape(-1, 4)
    intersection = np.maximum(0, np.minimum(box[2:], boxes[:, 2:]) -
                              np.maximum(box[:2], boxes[:, :2])).prod(axis=1)
    return intersection / ((box[2:] - box[:2]).prod() +
                           (boxes[:, 2:] - boxes[:, :2]).prod(axis=1) - intersection)


def yolo_line(class_id, points, box, width, height):
    size = np.array([width, height])
    center = (box[:2] + box[2:]) / 2 / size
    extent = (box[2:] - box[:2]) / size
    keypoints = np.c_[points / size, np.full(21, 2)].ravel()
    return str(class_id) + ' ' + ' '.join(f'{v:.9f}' for v in np.r_[center, extent, keypoints])


def read_labels(path, width, height):
    rows = [np.array(line.split(), dtype=float) for line in path.read_text().splitlines()]
    boxes = []
    for row in rows:
        center = row[1:3] * [width, height]
        extent = row[3:5] * [width, height]
        boxes.append(np.r_[center - extent / 2, center + extent / 2])
    return rows, boxes


def write_records(output, records, counts):
    (output / 'records.json').write_text(json.dumps(records))
    (output / 'counts.json').write_text(json.dumps(dict(counts), indent=2) + '\n')
    print(json.dumps(dict(counts), indent=2), flush=True)


def measure_margins(hagrid, output):
    margins = []
    for path in sorted((hagrid / 'labels/train').glob('*.txt')):
        with Image.open(hagrid / 'images/train' / (path.stem + '.jpg')) as image:
            width, height = image.size
        rows, boxes = read_labels(path, width, height)
        for row, box in zip(rows, boxes):
            points = row[5:].reshape(21, 3)
            if np.all(points[:, 2] > 0):
                xy = points[:, :2] * [width, height]
                low, high = xy.min(0), xy.max(0)
                margins.append(np.r_[low - box[:2], box[2:] - high] / (high - low).max())
    result = np.median(margins, axis=0).tolist()
    output.write_text(json.dumps(result) + '\n')
    print('margins_left_top_right_bottom', result, 'hands', len(margins), flush=True)


if __name__ == '__main__':
    import sys
    measure_margins(Path(sys.argv[1]), Path(sys.argv[2]))
