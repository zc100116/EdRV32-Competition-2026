#!/usr/bin/env python3
"""validate.py — R5-6: camera-on-tablet COCO detection measurement.

Host-only; use repository YOLO INT8 descriptors and integer postprocessing.
Run from repository root with tools/npu and ultralytics on PYTHONPATH.
"""
import json
from pathlib import Path

import cv2
import numpy as np
import torch

from fixed_plan import build_plan, descriptors
from format import BASES
from models_eval import integer
from quantize import load_quantized, prepare_image
from ref.npu_ref import Memory
from yolo_post_ref import make_heads

OUT = Path('outputs/farm-sim')
BUILD = Path('build/farm-sim')
CLASSES = dict(cow=19, horse=17, sheep=18, chicken=14, duck=14)
NAMES = {19: 'cow', 17: 'horse', 18: 'sheep', 14: 'bird'}
SOURCE = np.float32([[0, 0], [2000, 0], [2000, 1200], [0, 1200]])
DEST = np.float32([[220, 100], [1052, 112], [1044, 614], [228, 603]])
MATRIX = cv2.getPerspectiveTransform(SOURCE, DEST)


def photograph(name):
    source = cv2.imread(str(OUT / (name + '.png')))
    background = np.full((720, 1280, 3), (65, 64, 61), np.uint8)
    cv2.fillConvexPoly(background, np.int32([[206, 86], [1066, 98],
                                         [1058, 628], [214, 617]]), (24, 25, 24))
    frame = cv2.warpPerspective(source, MATRIX, (1280, 720))
    mask = cv2.warpPerspective(np.full((1200, 2000), 255, np.uint8), MATRIX, (1280, 720))
    background[mask > 0] = frame[mask > 0]
    frame = cv2.GaussianBlur(background, (7, 7), 1.0).astype(float) * .85
    frame += np.random.default_rng(17).normal(0, 2, frame.shape)
    frame = np.uint8(np.clip(frame, 0, 255))
    path = OUT / (name + '-camera.png')
    cv2.imwrite(str(path), frame)
    return path, frame


def expected_box(a):
    x, y, w, h = [a[key] for key in ('x', 'y', 'w', 'h')]
    points = np.float32([[[x-w/2, y-h/2], [x+w/2, y-h/2],
                         [x+w/2, y+h/2], [x-w/2, y+h/2]]])
    points = cv2.perspectiveTransform(points, MATRIX)[0]
    return np.r_[points.min(0), points.max(0)]


def overlap(a, b):
    area = np.maximum(0, np.minimum(a[2:], b[2:]) - np.maximum(a[:2], b[:2])).prod()
    return area / (np.prod(a[2:]-a[:2]) + np.prod(b[2:]-b[:2]) - area)


def main():
    torch.set_num_threads(1)
    plan = build_plan('detect')
    model, rows = load_quantized(plan)
    memory = Memory()
    memory.write(BASES['MODEL_BASE'], model)
    desc = descriptors(plan, rows)
    memory.write(BASES['DESC_BASE'], b''.join(d.encode() for d in desc))
    registers = BASES | {'DESC_COUNT': len(desc)}
    heads = make_heads({'convolutions': rows})
    positions = json.loads((BUILD / 'positions.json').read_text())
    measurements = {}
    passed = True
    for name, animals in positions.items():
        path, annotated = photograph(name)
        boxes, scores, ids, _ = integer(memory, registers, plan, rows, heads, prepare_image(path))
        # 1280x720 letterbox is 640x360 plus twelve rows above and below.
        boxes = (boxes - [0, 12, 0, 12]) * 2
        for box, score, cls in zip(boxes, scores, ids):
            x1, y1, x2, y2 = np.int32(box)
            cv2.rectangle(annotated, (x1, y1), (x2, y2), (80, 255, 180), 2)
            cv2.putText(annotated, f'{NAMES.get(int(cls), str(cls))} {score:.3f}',
                        (x1, y1-6), cv2.FONT_HERSHEY_SIMPLEX, .45, (80, 255, 180), 1)
        cv2.imwrite(str(OUT / (name + '-detections.png')), annotated)
        used = set()
        results = []
        for a in animals:
            # The escaped sheep is deliberately absent during the loss scene.
            if a['y']+a['h']/2 < 0:
                results.append(dict(id=a['id'], kind=a['kind'], absent=True))
                continue
            truth = expected_box(a)
            order = sorted((i for i in range(len(boxes)) if i not in used),
                           key=lambda i: overlap(truth, boxes[i]), reverse=True)
            i = order[0] if order else None
            detected = i is not None and overlap(truth, boxes[i]) >= .35
            result = dict(id=a['id'], kind=a['kind'], detected=bool(detected))
            if detected:
                used.add(i)
                result.update(category=NAMES.get(int(ids[i]), str(ids[i])),
                              confidence=float(scores[i]))
            ok = detected and ids[i] == CLASSES[a['kind']] and scores[i] >= .4
            result['pass'] = bool(ok)
            passed &= bool(ok)
            results.append(result)
        measurements[name] = results
        print(name, json.dumps(results))
    (BUILD / 'detections.json').write_text(json.dumps(measurements, indent=2))
    if not passed:
        raise SystemExit('FAIL: each visible animal must match its COCO class at confidence >=0.4')
    print('PASS: all visible animals correctly detected at confidence >=0.4')


if __name__ == '__main__':
    main()
