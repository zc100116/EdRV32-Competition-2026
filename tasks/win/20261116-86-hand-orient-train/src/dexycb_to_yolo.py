#!/usr/bin/env python3
"""dexycb_to_yolo.py: card 86 steps 3a/5, approach-only DexYCB conversion.
Clock domain: not applicable (offline dataset conversion).
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import numpy as np
import yaml
from ultralytics import YOLO
from data_common import hand_box, iou, outside, write_records, yolo_line
from hand3d_gesture import classify, orientation, NAMES


def convert(root, output, margins, weights):
    rng = np.random.default_rng(0)
    counts = Counter()
    candidates = {'train': [], 'val': []}
    model = YOLO(str(weights))
    for subject in sorted(root.glob('*subject-0[123]')):
        split = 'val' if subject.name.endswith('03') else 'train'
        for sequence in sorted(subject.iterdir()):
            meta = yaml.safe_load((sequence / 'meta.yml').read_text())
            side = meta['mano_sides'][0]
            grasp = meta['ycb_grasp_ind']
            for camera in sorted(p for p in sequence.iterdir() if p.is_dir()):
                paths = sorted(camera.glob('labels_*.npz'))
                with np.load(paths[0]) as data:
                    initial = data['pose_y'][grasp, :, 3]
                onset = len(paths)
                for frame, path in enumerate(paths):
                    with np.load(path) as data:
                        position = data['pose_y'][grasp, :, 3]
                    if np.linalg.norm(position - initial) > 0.005:
                        onset = frame
                        break
                for frame in range(0, len(paths), 10):
                    counts[f'{split}/sampled'] += 1
                    if frame >= onset - 15:
                        counts[f'{split}/after_approach'] += 1
                        continue
                    with np.load(paths[frame]) as data:
                        uv = data['joint_2d'].reshape(21, 2)
                        xyz = data['joint_3d'].reshape(21, 3)
                    if np.any(uv == -1):
                        counts[f'{split}/no_hand'] += 1
                        continue
                    if outside(uv, 640, 480):
                        counts[f'{split}/outside_image'] += 1
                        continue
                    class_id = classify(xyz, uv)
                    counts[f'{split}/classified'] += 1
                    if class_id is None:
                        counts[f'{split}/uncertain'] += 1
                        continue
                    box = hand_box(uv, margins)
                    image = camera / f'color_{frame:06d}.jpg'
                    prediction = model.predict(str(image), conf=0.25, verbose=False)[0]
                    detections = prediction.boxes.xyxy.cpu().numpy()
                    if np.any(iou(box, detections) < 0.3):
                        counts[f'{split}/unannotated_hand'] += 1
                        continue
                    name = f'{subject.name}_{sequence.name}_{camera.name}_{frame:06d}'
                    candidates[split].append(dict(source=str(image), id=name, split=split,
                                                  class_id=class_id, points=uv.tolist(),
                                                  box=box.tolist(),
                                                  orientation=orientation(xyz, side),
                                                  visible=[True] * 21))
    records = []
    for split, limit in [('train', 20000), ('val', 3000)]:
        items = candidates[split]
        indices = rng.choice(len(items), min(limit, len(items)), replace=False)
        image_dir = output / 'images' / split
        label_dir = output / 'labels' / split
        image_dir.mkdir(parents=True)
        label_dir.mkdir(parents=True)
        for index in indices:
            item = items[int(index)]
            image = image_dir / (item['id'] + '.jpg')
            os.link(item['source'], image)
            uv = np.array(item['points'])
            box = np.array(item['box'])
            label = yolo_line(item['class_id'], uv, box, 640, 480)
            (label_dir / (item['id'] + '.txt')).write_text(label + '\n')
            item['image'] = str(image)
            records.append(item)
            counts[f"{split}/{NAMES[item['class_id']]}/{item['orientation']}"] += 1
    write_records(output, records, counts)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('margins', type=Path)
    parser.add_argument('weights', type=Path)
    args = parser.parse_args()
    convert(args.root, args.output, json.loads(args.margins.read_text()), args.weights)
