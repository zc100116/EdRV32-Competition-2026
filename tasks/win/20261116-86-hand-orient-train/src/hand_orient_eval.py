#!/usr/bin/env python3
"""hand_orient_eval.py: card 86 step 8, class-agnostic IoU detection and PCK.
PCK includes all labeled visible points; undetected hands contribute zero hits.
Clock domain: not applicable (offline model evaluation).
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import cv2
import numpy as np
from ultralytics import YOLO
from data_common import iou, read_labels


def ground_truth(root, dataset):
    if dataset != 'hagrid':
        return [r for r in json.loads((root / 'records.json').read_text()) if r['split'] == 'val']
    records = []
    for image in sorted((root / 'images/val').glob('*.jpg')):
        pixels = cv2.imread(str(image))
        height, width = pixels.shape[:2]
        rows, boxes = read_labels(root / 'labels/val' / (image.stem + '.txt'), width, height)
        for row, box in zip(rows, boxes):
            keypoints = row[5:].reshape(21, 3)
            records.append(dict(image=str(image), class_id=int(row[0]), box=box.tolist(),
                                points=(keypoints[:, :2] * [width, height]).tolist(),
                                visible=(keypoints[:, 2] > 0).tolist(), orientation='unknown'))
    return records


def evaluate(weights, root, dataset, output):
    model = YOLO(str(weights))
    groups = defaultdict(list)
    for item in ground_truth(root, dataset):
        groups[item['image']].append(item)
    counts = defaultdict(lambda: np.zeros(5, dtype='int64'))
    for image, items in groups.items():
        prediction = model.predict(image, conf=0.25, imgsz=640, verbose=False)[0]
        boxes = prediction.boxes.xyxy.cpu().numpy()
        classes = prediction.boxes.cls.cpu().numpy().astype(int)
        points = prediction.keypoints.xy.cpu().numpy()
        overlaps = np.array([iou(np.array(item['box']), boxes) for item in items])
        matches = {}
        for flat in np.argsort(overlaps.ravel())[::-1]:
            gt, pred = np.unravel_index(flat, overlaps.shape)
            if overlaps[gt, pred] < 0.5:
                break
            if gt not in matches and pred not in matches.values():
                matches[gt] = pred
        for index, item in enumerate(items):
            visible = np.array(item['visible'])
            values = np.array([1, 0, 0, 0, visible.sum()], dtype='int64')
            if index in matches:
                pred = matches[index]
                values[1] = 1
                if dataset == 'hagrid':
                    values[2] = classes[pred] == item['class_id']
                error = np.linalg.norm(points[pred] - np.array(item['points']), axis=1)
                box = np.array(item['box'])
                values[3] = np.sum((error < 0.1 * (box[2:] - box[:2]).max()) & visible)
            counts['all'] += values
            counts[item['orientation']] += values
    result = {}
    for group, values in counts.items():
        hands, detected, correct, hits, total = map(int, values)
        result[group] = dict(hands=hands, detected=detected, class_correct=correct,
                             pck_hits=hits, labeled_points=total,
                             detection_rate=detected / hands,
                             class_accuracy=(correct / detected if detected else None)
                             if dataset == 'hagrid' else None,
                             pck=hits / total if total else None)
    if dataset != 'hagrid':
        for values in result.values():
            del values['class_correct']
            del values['class_accuracy']
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('weights', type=Path)
    parser.add_argument('root', type=Path)
    parser.add_argument('dataset', choices=['hagrid', 'freihand', 'dexycb'])
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    evaluate(args.weights, args.root, args.dataset, args.output)
