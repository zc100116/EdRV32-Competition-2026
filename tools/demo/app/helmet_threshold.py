#!/usr/bin/env python3
"""T-HELMET-STABLE: helmet INT8 scores on two photographed Paparazzi sequences.

Run from repository root with PYTHONPATH=tools/npu:tools/demo/app and edrv32-py.
Clock: offline host. Inputs/outputs live under build/demo-app and build/helmet-stable.
"""
import json
from pathlib import Path
import math
import cv2
import numpy as np
import torch
import validate
from compile_yolo import read_model_hex
from fixed_plan import build_plan, descriptors
from format import BASES
from models_eval import integer
from quantize import prepare_image
from ref.npu_ref import Memory
from yolo_post_ref import make_heads

OUT = Path('build/helmet-stable')
SOURCE = Path('sw/apps/showcase/models/helmet')
DEST = np.float32([[260, 65], [1050, 150], [996, 650], [170, 565]])
SEVERE = cv2.getPerspectiveTransform(validate.kit.SOURCE, DEST)


def severe(frame):
    stage = np.full((1200, 2000, 3), (45, 37, 20), np.uint8)
    stage[:1125] = cv2.resize(frame, (2000, 1125))
    photo = np.full((720, 1280, 3), (65, 64, 61), np.uint8)
    projected = cv2.warpPerspective(stage, SEVERE, (1280, 720))
    mask = cv2.warpPerspective(np.full((1200, 2000), 255, np.uint8), SEVERE, (1280, 720))
    photo[mask > 0] = projected[mask > 0]
    photo = cv2.GaussianBlur(photo, (9, 9), 1.5).astype(float) * [.85, .91, .70]
    photo += np.random.default_rng(17).normal(0, 4, photo.shape)
    return np.uint8(np.clip(photo, 0, 255))


def workers(row):
    # SiteModel.kt positions and wearing state; each sprite is 318.5 x 490 pixels.
    initial = [(360, 385), (940, 360), (1530, 365), (520, 865), (1100, 865), (1680, 865)]
    seconds = row['seconds']
    demo = not row['static']
    result = []
    for worker, (x, y) in enumerate(initial):
        moving = not (demo and seconds < 5) and worker in (0, 1, 4)
        if moving:
            x += math.sin(seconds*.32+worker)*32
            y += math.sin(seconds*.28+worker)*9
        wearing = not (worker == 0 and 5.5 <= seconds < 10.5) if demo else worker < 4
        result.append((x, y, wearing))
    if demo and 14 <= seconds < 23:
        x = -220+330*min((seconds-14)/2, 1) if seconds < 21 else 110-330*(seconds-21)/2
        result.append((x, 850, False))
    return result


def evaluate():
    torch.set_num_threads(1)
    OUT.mkdir(parents=True, exist_ok=True)
    quant = json.loads((SOURCE / 'quantization.json').read_text())
    plan = build_plan('detect', 2, 0)
    encoded = descriptors(plan, quant['convolutions'])
    memory = Memory()
    memory.write(BASES['MODEL_BASE'], read_model_hex(SOURCE/'mem_model.hex', BASES['MODEL_BASE']))
    memory.write(BASES['DESC_BASE'], b''.join(d.encode() for d in encoded))
    registers = BASES | {'DESC_COUNT': len(encoded)}
    heads = make_heads(quant)
    rows = json.loads(Path('build/demo-app/site-frames.json').read_text())
    results = {}
    for name, photograph, matrix in [('original', validate.kit.photograph, validate.kit.MATRIX),
                                      ('severe', severe, SEVERE)]:
        measurements = []
        scores_true, scores_false, targets = [], [], 0
        for row in rows:
            frame = cv2.imread('build/demo-app/site-frames/'+row['file'])
            photo = photograph(frame)
            path = OUT / (name+'-'+row['file'])
            cv2.imwrite(str(path), photo)
            boxes, scores, classes, _ = integer(memory, registers, plan, quant['convolutions'],
                                               heads, prepare_image(path))
            boxes = (boxes-[0, 12, 0, 12])*2
            people = workers(row)
            regions = [(x-159.25, y-245, x+159.25, y-105) for x, y, wearing in people
                       if wearing]
            targets += len(regions)
            found = {}
            false = []
            for box, score, cls in zip(boxes, scores, classes):
                if cls != 0:
                    continue
                center = np.float32([[[(box[0]+box[2])/2, (box[1]+box[3])/2]]])
                x, y = cv2.perspectiveTransform(center, np.linalg.inv(matrix))[0, 0]
                matches = [i for i, (x1, y1, x2, y2) in enumerate(regions)
                           if x1 <= x <= x2 and y1 <= y <= y2]
                if matches:
                    i = matches[0]
                    found[i] = max(float(score), found.get(i, 0))
                elif not any(abs(x-px) <= 159.25 and abs(y-py) <= 245
                             for px, py, _ in people):
                    false.append(float(score))
            scores_true.extend(found.values())
            scores_false.extend(false)
            measurement = row | dict(targets=len(regions), true_scores=list(found.values()),
                                     false_scores=false, boxes=boxes.tolist(),
                                     scores=scores.tolist(), classes=classes.tolist())
            measurements.append(measurement)
            print(name, row['file'], 'true', list(found.values()), 'false', false, flush=True)
        distribution = np.percentile(scores_true, [0, 5, 50, 95, 100]).tolist()
        summary = dict(targets=targets, detected=len(scores_true), true_percentiles=distribution,
                       false_count=len(scores_false), false_max=max(scores_false, default=0),
                       threshold=.60, recalled=sum(s >= .60 for s in scores_true))
        summary['recall'] = summary['recalled']/targets
        results[name] = dict(summary=summary, frames=measurements)
        (OUT / 'threshold-results.json').write_text(json.dumps(results, indent=2))
        print(name, summary, flush=True)


if __name__ == '__main__':
    evaluate()
