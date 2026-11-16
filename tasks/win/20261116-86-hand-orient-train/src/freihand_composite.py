#!/usr/bin/env python3
"""freihand_composite.py: card 86, class-ignored FreiHAND hand composites.
Applies the approved geometry, edge, colour and split requirements.
Clock domain: not applicable (offline image synthesis).
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import cv2
import numpy as np
from data_common import hand_box, iou, outside, read_labels, write_records, yolo_line
from hand3d_gesture import orientation


def prepare(root, counts, margins):
    xyzs = np.array(json.loads((root / 'training_xyz.json').read_text()))
    cameras = np.array(json.loads((root / 'training_K.json').read_text()))
    samples = {'train': [], 'val': []}
    for index in range(32560):
        split = 'train' if index < 30932 else 'val'
        counts[f'source/{split}/input'] += 1
        xyz = xyzs[index]
        projected = xyz @ cameras[index].T
        points = projected[:, :2] / projected[:, 2:]
        if outside(points, 224, 224):
            counts[f'source/{split}/outside_image'] += 1
            continue
        mask = cv2.imread(str(root / 'training/mask' / f'{index:08d}.jpg'), 0)
        expanded = cv2.dilate((mask > 127).astype('uint8'), np.ones((11, 11), 'uint8'))
        pixels = np.floor(points).astype(int)
        if np.any(expanded[pixels[:, 1], pixels[:, 0]] == 0):
            counts[f'source/{split}/outside_mask'] += 1
            continue
        box = hand_box(points, margins)
        extent = box[2:] - box[:2]
        if extent.max() / extent.min() > 3:
            counts[f'source/{split}/aspect_gt3'] += 1
            continue
        facing = orientation(xyz)
        samples[split].append(dict(source_id=index, points=points.tolist(), class_id=14,
                                   orientation=facing))
        counts[f'source/{split}/retained/{facing}'] += 1
    return samples


def feather_alpha(alpha):
    return cv2.GaussianBlur(alpha, (7, 7), 1)


def mask_and_colour(patch, mask, rng):
    binary = (mask > 127).astype('uint8')
    inside = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    outside_mask = cv2.distanceTransform(1 - binary, cv2.DIST_L2, 5)
    edge = ((inside > 0) & (inside <= 3)) | ((outside_mask > 0) & (outside_mask <= 3))
    patch = patch.copy()
    # Suppress only excess green in the explicitly approved 3 px edge band.
    green_limit = np.maximum(patch[:, :, 0], patch[:, :, 2])
    patch[:, :, 1][edge] = np.minimum(patch[:, :, 1], green_limit)[edge]
    hsv = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV).astype('float32')
    hsv[:, :, 1] *= rng.uniform(0.95, 1.05)
    hsv[:, :, 2] *= rng.uniform(0.9, 1.1)
    patch = cv2.cvtColor(np.clip(hsv, 0, 255).astype('uint8'), cv2.COLOR_HSV2BGR)
    eroded = cv2.erode(binary, np.ones((3, 3), 'uint8')).astype('float32')
    return patch.astype('float32'), feather_alpha(eroded)


def transform(root, sample, height, rng, margins, counts, split):
    index = sample['source_id']
    points = np.array(sample['points'])
    matrix = cv2.getRotationMatrix2D((112, 112), rng.uniform(-45, 45), 1)
    matrix[:, 0] *= -1 if rng.random() < 0.5 else 1
    moved = np.c_[points, np.ones(21)] @ matrix.T
    box = hand_box(moved, margins)
    extent = box[2:] - box[:2]
    if extent.max() / extent.min() > 3:
        counts[f'{split}/transformed_aspect_gt3'] += 1
        return None
    minimum = height * 0.08
    maximum = min(height * 0.30, extent.max() * 1.5)
    if maximum < minimum:
        counts[f'{split}/scale_infeasible'] += 1
        return None
    matrix *= rng.uniform(minimum, maximum) / extent.max()
    corners = np.array([[0, 0, 1], [224, 0, 1], [0, 224, 1], [224, 224, 1]]) @ matrix.T
    low, high = corners.min(0), corners.max(0)
    matrix[:, 2] -= low
    size = tuple(np.ceil(high - low).astype(int))
    image = cv2.imread(str(root / 'training/rgb' / f'{index:08d}.jpg'))
    mask = cv2.imread(str(root / 'training/mask' / f'{index:08d}.jpg'), 0)
    patch = cv2.warpAffine(image, matrix, size)
    warped_mask = cv2.warpAffine(mask, matrix, size)
    patch, alpha = mask_and_colour(patch, warped_mask, rng)
    moved = np.c_[points, np.ones(21)] @ matrix.T
    return patch, alpha, moved, sample['orientation']


def composite(root, hagrid, mixed, output, margins, split):
    rng = np.random.default_rng(0)
    counts = Counter()
    sample_groups = prepare(root, counts, margins)
    samples = sample_groups[split]
    if split == 'train':
        previous = json.loads((output / 'counts.json').read_text())
        counts.update({key: value for key, value in previous.items() if key.startswith('val/')})
        records = json.loads((output / 'records.json').read_text())
    else:
        records = []
    backgrounds = sorted((hagrid / 'images' / split).glob('*.jpg'))
    if split == 'train':
        excluded = {Path(name).stem for name in
                    (mixed / 'hagrid-train.txt').read_text().splitlines()}
        backgrounds = [path for path in backgrounds if path.stem not in excluded]
    counts[f'{split}/background_pool'] = len(backgrounds)
    image_dir = output / 'images' / split
    label_dir = output / 'labels' / split
    image_dir.mkdir(parents=True)
    label_dir.mkdir(parents=True)
    number = 0
    total = 1500 if split == 'val' else 25000
    # Rejection sampling enforces the approved non-overlap and dataset size.
    while number < total:
        background = backgrounds[int(rng.integers(len(backgrounds)))]
        canvas = cv2.imread(str(background))
        height, width = canvas.shape[:2]
        original = hagrid / 'labels' / split / (background.stem + '.txt')
        _, occupied = read_labels(original, width, height)
        labels = original.read_text().splitlines()
        pasted = []
        for _ in range(int(rng.integers(1, 3))):
            sample = samples[int(rng.integers(len(samples)))]
            transformed = transform(root, sample, height, rng, margins, counts, split)
            if transformed is None:
                continue
            patch, alpha, points, facing = transformed
            ph, pw = patch.shape[:2]
            if ph >= height or pw >= width:
                counts[f'{split}/transform_not_placed'] += 1
                continue
            box = hand_box(points, margins)
            mx, my, mw, mh = cv2.boundingRect((alpha > 0).astype('uint8'))
            cutout = np.array([mx, my, mx + mw, my + mh])
            offsets = rng.uniform([0, 0], [width - pw, height - ph], (128, 2)).astype(int)
            selected = None
            for offset in offsets:
                moved_box = box + np.tile(offset, 2)
                moved_cutout = cutout + np.tile(offset, 2)
                if (not np.any(iou(moved_box, occupied) > 0) and
                        not np.any(iou(moved_cutout, occupied) > 0)):
                    selected = offset
                    break
            if selected is None:
                counts[f'{split}/no_space'] += 1
                continue
            x, y = selected
            canvas[y:y+ph, x:x+pw] = (patch * alpha[:, :, None] +
                                    canvas[y:y+ph, x:x+pw] * (1 - alpha[:, :, None]))
            points = points + selected
            box = box + np.tile(selected, 2)
            labels.append(yolo_line(14, points, box, width, height))
            occupied.extend([box, cutout + np.tile(selected, 2)])
            pasted.append(dict(class_id=14, points=points.tolist(), box=box.tolist(),
                               orientation=facing, source_id=sample['source_id'],
                               visible=[True] * 21))
            counts[f'{split}/ignore_class/{facing}'] += 1
        if not pasted:
            counts[f'{split}/empty_composite'] += 1
            continue
        name = f'fh_{number:06d}'
        image = image_dir / (name + '.png')
        cv2.imwrite(str(image), canvas)
        (label_dir / (name + '.txt')).write_text('\n'.join(labels) + '\n')
        for item in pasted:
            item.update(image=str(image), split=split, background=str(background))
            records.append(item)
        counts[f'{split}/images'] += 1
        number += 1
    write_records(output, records, counts)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('hagrid', type=Path)
    parser.add_argument('mixed', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('margins', type=Path)
    parser.add_argument('split', choices=['val', 'train'])
    args = parser.parse_args()
    composite(args.root, args.hagrid, args.mixed, args.output,
              json.loads(args.margins.read_text()), args.split)
