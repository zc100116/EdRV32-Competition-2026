#!/usr/bin/env python3
"""freihand_prepare.py: card 86 revised step 2/6, local filtering and review.
Writes selected sample annotations and tar input names for the approved upload.
Clock domain: not applicable (offline preprocessing).
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import numpy as np
import cv2
from data_common import hand_box, write_records, outside
from hand3d_gesture import NAMES, classify, orientation

def prepare(root, counts):
    xyzs = np.array(json.loads((root / 'training_xyz.json').read_text()))
    cameras = np.array(json.loads((root / 'training_K.json').read_text()))
    samples = {'train': [], 'val': []}
    for index in range(32560):
        split = 'train' if index < 30932 else 'val'
        counts[f'{split}/input'] += 1
        xyz = xyzs[index]
        projected = xyz @ cameras[index].T
        uv = projected[:, :2] / projected[:, 2:]
        if outside(uv, 224, 224):
            counts[f'{split}/outside_image'] += 1
            continue
        mask = cv2.imread(str(root / 'training/mask' / f'{index:08d}.jpg'), 0)
        expanded = cv2.dilate((mask > 127).astype('uint8'), np.ones((11, 11), 'uint8'))
        pixels = np.floor(uv).astype(int)
        if np.any(expanded[pixels[:, 1], pixels[:, 0]] == 0):
            counts[f'{split}/outside_mask'] += 1
            continue
        counts[f'{split}/classified'] += 1
        class_id = classify(xyz, uv)
        if class_id is None:
            counts[f'{split}/uncertain'] += 1
            continue
        samples[split].append((index, xyz, uv, class_id, orientation(xyz)))
    return samples


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('root', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('margins', type=Path)
args = parser.parse_args()
counts = Counter()
samples = prepare(args.root, counts)
margins = json.loads(args.margins.read_text())
records = []
annotations = []
files = []
args.output.mkdir(parents=True)
for split, items in samples.items():
    for index, xyz, points, class_id, facing in items:
        item = dict(source_id=index, split=split, class_id=class_id, points=points.tolist(),
                    orientation=facing, visible=[True] * 21)
        annotations.append(item)
        image = (args.root / 'training/rgb' / f'{index:08d}.jpg').resolve()
        reviewed = dict(item, image=str(image),
                        box=hand_box(points, margins).tolist())
        records.append(reviewed)
        files += [f'training/rgb/{index:08d}.jpg', f'training/mask/{index:08d}.jpg']
        counts[f'{split}/{NAMES[class_id]}/{facing}'] += 1
write_records(args.output, records, counts)
(args.output / 'annotations.json').write_text(json.dumps(annotations))
(args.output / 'selected-files.txt').write_text('\n'.join(files) + '\n')
