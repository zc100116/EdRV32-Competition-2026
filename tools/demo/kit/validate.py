#!/usr/bin/env python3
"""validate.py — showcase R5-8/9: INT8 simulated tablet-camera acceptance.

Use unchanged board models, confidence >0.25 and same-class NMS IoU >0.45.
Host tool; intermediate frames and measurements stay under build/demo-kit/.
"""
from collections import Counter
import gc
import json
from math import ceil
from pathlib import Path
import sys

import cv2
import numpy as np
import torch
from ultralytics import YOLO

from fixed_plan import build_plan, descriptors
from format import BASES
from model_data import weights_for
from models_eval import integer
from quantize import load_quantized, prepare_image
from ref.npu_ref import Memory
from yolo_post_ref import make_heads

ROOT = Path(__file__).resolve().parent
BUILD = Path('build/demo-kit')
OUT = Path('outputs/demo-kit')
SOURCE = np.float32([[0, 0], [2000, 0], [2000, 1200], [0, 1200]])
DEST = np.float32([[220, 100], [1052, 112], [1044, 614], [228, 603]])
MATRIX = cv2.getPerspectiveTransform(SOURCE, DEST)
COCO = {0: 'person', 9: 'traffic-light', 1: 'bicycle', 2: 'car', 3: 'motorcycle',
        5: 'bus', 7: 'truck',
        20: 'elephant', 21: 'bear', 22: 'zebra', 23: 'giraffe'}
GESTURES = ['palm', 'fist', 'peace', 'point', 'grabbing', 'grip', 'thumb_index',
            'ok', 'like', 'dislike', 'three', 'four', 'call', 'no_gesture']


def photograph(frame):
    stage = np.full((1200, 2000, 3), (45, 37, 20), np.uint8)
    stage[:1125] = cv2.resize(frame, (2000, 1125))
    background = np.full((720, 1280, 3), (65, 64, 61), np.uint8)
    cv2.fillConvexPoly(background, np.int32([[206, 86], [1066, 98],
                                         [1058, 628], [214, 617]]), (24, 25, 24))
    projection = cv2.warpPerspective(stage, MATRIX, (1280, 720))
    mask = cv2.warpPerspective(np.full((1200, 2000), 255, np.uint8), MATRIX, (1280, 720))
    background[mask > 0] = projection[mask > 0]
    frame = cv2.GaussianBlur(background, (7, 7), 1.0).astype(float) * .85
    frame += np.random.default_rng(17).normal(0, 2, frame.shape)
    return np.uint8(np.clip(frame, 0, 255))


def frames(item):
    if item['type'].startswith('image'):
        yield 0, cv2.imread(item['path'])
    else:
        capture = cv2.VideoCapture(item['path'])
        duration = capture.get(cv2.CAP_PROP_FRAME_COUNT) / capture.get(cv2.CAP_PROP_FPS)
        for second in range(ceil(duration)):
            capture.set(cv2.CAP_PROP_POS_MSEC, second * 1000)
            ok, frame = capture.read()
            if not ok:
                raise RuntimeError(f"Cannot decode {item['id']} at {second} s")
            yield second, frame
        capture.release()


def setup(name):
    if name == 'detect':
        plan = build_plan('detect')
        names = COCO
    elif name == 'pose':
        plan = build_plan('pose')
        names = {0: 'person'}
    else:
        weights = weights_for(name)
        network = YOLO(str(weights)).model.eval().fuse(verbose=False)
        head = network.model[-1]
        shape = getattr(head, 'kpt_shape', (0, 3))
        plan = build_plan('detect' if name == 'helmet' else name, head.nc, shape[0]*shape[1])
        plan.update(weights=str(weights.resolve()), dataset=name)
        names = network.names
        del network
    model, rows = load_quantized(plan)
    memory = Memory()
    memory.write(BASES['MODEL_BASE'], model)
    desc = descriptors(plan, rows)
    memory.write(BASES['DESC_BASE'], b''.join(d.encode() for d in desc))
    heads = make_heads({'convolutions': rows})
    return plan, rows, memory, BASES | {'DESC_COUNT': len(desc)}, heads, names


def contact_sheet(scene, samples):
    columns = 3
    rows = (len(samples) + columns - 1) // columns
    sheet = np.full((rows * 286, columns * 480, 3), (31, 32, 34), np.uint8)
    for i, (label, frame) in enumerate(samples):
        x, y = (i % columns) * 480, (i // columns) * 286
        sheet[y:y+270, x:x+480] = cv2.resize(frame, (480, 270))
        cv2.putText(sheet, label, (x+6, y+282), cv2.FONT_HERSHEY_SIMPLEX,
                    .4, (240, 240, 240), 1, cv2.LINE_AA)
    cv2.imwrite(str(OUT / (scene + '-contact.png')), sheet)


def evaluate(scene):
    scene_id = scene['id']
    model = {'traffic': 'detect', 'zoo': 'detect', 'dance': 'pose',
             'gesture': 'gesture', 'helmet': 'helmet', 'face': 'face'}[scene_id]
    plan, rows, memory, registers, heads, names = setup(model)
    results, samples = [], []
    for item in scene['items']:
        measurements = []
        all_classes = set()
        for second, source in frames(item):
            frame = photograph(source)
            path = BUILD / 'frames' / f"{item['id']}-{second:02d}.png"
            cv2.imwrite(str(path), frame)
            boxes, scores, ids, points = integer(memory, registers, plan, rows, heads,
                                                prepare_image(path))
            all_classes.update(map(int, ids))
            if scene_id == 'traffic':
                passed = sum(int(cls) in (1, 2, 3, 5, 7) for cls in ids) >= 2
            elif scene_id == 'zoo':
                expected = Counter({int(k): v for k, v in item['expected'].items()})
                passed = Counter(map(int, ids)) == expected
            elif scene_id == 'dance':
                passed = len(ids) == item['people'] and all(
                    np.count_nonzero(person[:, 2] > .5) >= 12 for person in points)
            elif scene_id == 'gesture':
                passed = ids.tolist() == [GESTURES.index(item['id'])]
            elif scene_id == 'helmet':
                passed = len(ids) > 0
            else:
                passed = len(ids) == item['people']
            measurement = dict(second=second, classes=ids.tolist(), scores=scores.tolist(),
                               visible_points=[int(sum(p[:, 2] > .5)) for p in points],
                               passed=bool(passed))
            measurements.append(measurement)
            boxes = (boxes - [0, 12, 0, 12]) * 2
            for box, score, cls, person in zip(boxes, scores, ids, points):
                x1, y1, x2, y2 = np.int32(box)
                cv2.rectangle(frame, (x1, y1), (x2, y2), (80, 255, 180), 2)
                label = f'{names.get(int(cls), str(cls))} {score:.2f}'
                cv2.putText(frame, label, (x1, max(18, y1-6)), cv2.FONT_HERSHEY_SIMPLEX,
                            .5, (80, 255, 180), 1, cv2.LINE_AA)
                for point in person:
                    if point[2] > .5:
                        xy = np.int32((point[:2]-[0, 12])*2)
                        cv2.circle(frame, tuple(xy), 3, (60, 180, 255), -1)
            cv2.imwrite(str(BUILD / 'frames' / f"{item['id']}-{second:02d}-detected.jpg"), frame)
            if second % 4 == 0:
                samples.append((f"{item['id']} {second}s {'PASS' if passed else 'FAIL'}", frame))
            print(scene_id, item['id'], measurement, flush=True)
        count = sum(m['passed'] for m in measurements)
        required = .9 if scene_id in ('traffic', 'dance', 'helmet') else 1
        passed = count / len(measurements) >= required
        if scene_id == 'helmet':
            passed &= {0, 1} <= all_classes
        results.append(dict(id=item['id'], passed=bool(passed), good=count,
                            samples=len(measurements), classes=sorted(all_classes),
                            frames=measurements))
    contact_sheet(scene_id, samples)
    (BUILD / (scene_id+'-results.json')).write_text(json.dumps(results, indent=2))
    del memory
    gc.collect()
    return results


def main():
    torch.set_num_threads(1)
    (BUILD / 'frames').mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    scenes = json.loads((ROOT / 'media.json').read_text())
    chosen = sys.argv[1:] or ['traffic', 'zoo', 'dance', 'gesture', 'helmet', 'face']
    results = {s['id']: evaluate(s) for s in scenes if s['id'] in chosen}
    if not all(r['passed'] for items in results.values() for r in items):
        raise SystemExit('FAIL: material does not meet fixed-threshold scene acceptance')
    print('PASS:', ', '.join(results), flush=True)


if __name__ == '__main__':
    main()
