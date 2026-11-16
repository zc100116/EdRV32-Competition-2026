#!/usr/bin/env python3
"""assemble_data.py: card 86 step 7, class-balanced HaGRID with half inverted.
Missing sampled images use card 83's original annotation-to-YOLO conversion.
Clock domain: not applicable (offline dataset assembly).
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import numpy as np
import yaml

GROUPS = [('palm', 'stop', 'stop_inverted'), ('fist',),
          ('peace', 'peace_inverted', 'two_up', 'two_up_inverted'), ('one', 'point'),
          ('grabbing',), ('grip',), ('thumb_index',), ('ok',), ('like',), ('dislike',),
          ('three', 'three2', 'three3'), ('four',), ('call',), ('no_gesture',)]
CLASS_IDS = {source: i for i, sources in enumerate(GROUPS) for source in sources}
INVERTED = {'stop_inverted', 'peace_inverted', 'two_up_inverted'}


def convert_annotation(annotation):
    # Same class map, box convention, visibility and missing-point values as card 83.
    lines = []
    for hand, label in enumerate(annotation['labels']):
        x, y, width, height = annotation['bboxes'][hand]
        values = [CLASS_IDS[label], x + width / 2, y + height / 2, width, height]
        landmarks = annotation['hand_landmarks']
        points = landmarks[hand] if landmarks else None
        for point in points or [[0, 0]] * 21:
            values.extend([*point, 2 if points else 0])
        lines.append(' '.join(map(str, values)))
    return '\n'.join(lines) + '\n'


def sample_hagrid(hagrid, output):
    rng = np.random.default_rng(0)
    per_class = round(60000 / 14)
    existing = {p.stem for p in (hagrid / 'images/train').glob('*.jpg')}
    source_root = hagrid.parent / 'HaGRIDv2_dataset_512'
    output.mkdir(parents=True)
    image_dir = output / 'images/train'
    label_dir = output / 'labels/train'
    image_dir.mkdir(parents=True)
    label_dir.mkdir(parents=True)
    train = []
    counts = Counter()
    for class_id, sources in enumerate(GROUPS):
        candidates = {}
        for source in sources:
            path = hagrid.parent / 'annotations/annotations/train' / (source + '.json')
            for name, annotation in json.loads(path.read_text()).items():
                if class_id in (0, 2) or name in existing:
                    candidates[name] = (source, annotation)
        pools = [sorted(candidates)]
        sizes = [min(per_class, len(candidates))]
        if class_id in (0, 2):
            pools = [sorted(n for n, (s, _) in candidates.items() if s in INVERTED),
                     sorted(n for n, (s, _) in candidates.items() if s not in INVERTED)]
            sizes = [per_class // 2, per_class - per_class // 2]
        for pool, size in zip(pools, sizes):
            for name in rng.choice(pool, size, replace=False):
                source, annotation = candidates[name]
                if name in existing:
                    image = hagrid / 'images/train' / (name + '.jpg')
                else:
                    image = image_dir / (name + '.jpg')
                    os.link(source_root / source / (name + '.jpg'), image)
                    (label_dir / (name + '.txt')).write_text(convert_annotation(annotation))
                    counts['hagrid_added_from_raw'] += 1
                train.append(str(image))
                counts[f'hagrid_class_{class_id}'] += 1
                counts[f'hagrid_source_{source}'] += 1
    val = [str(p) for p in sorted((hagrid / 'images/val').glob('*.jpg'))]
    counts['hagrid_train'] = len(train)
    counts['hagrid_val'] = len(val)
    (output / 'hagrid-train.txt').write_text('\n'.join(train) + '\n')
    (output / 'hagrid-val.txt').write_text('\n'.join(val) + '\n')
    (output / 'hagrid-counts.json').write_text(json.dumps(counts, indent=2) + '\n')
    config = yaml.safe_load((hagrid / 'hagrid.yaml').read_text())
    config.update(path=str(output), train='train.txt', val='val.txt')
    (output / 'hand-orient.yaml').write_text(yaml.safe_dump(config, sort_keys=False))
    print(json.dumps(counts, indent=2), flush=True)


def mix(freihand, output):
    train = (output / 'hagrid-train.txt').read_text().splitlines()
    val = (output / 'hagrid-val.txt').read_text().splitlines()
    counts = json.loads((output / 'hagrid-counts.json').read_text())
    images = sorted((freihand / 'images/train').glob('*.jpg'))
    valid = sorted((freihand / 'images/val').glob('*.jpg'))
    train.extend(map(str, images))
    # Unknown-class FreiHAND is evaluated separately; native training val is HaGRID.
    (output / 'freihand-val.txt').write_text('\n'.join(map(str, valid)) + '\n')
    counts['freihand_train'] = len(images)
    counts['freihand_val'] = len(valid)
    (output / 'train.txt').write_text('\n'.join(train) + '\n')
    (output / 'val.txt').write_text('\n'.join(val) + '\n')
    (output / 'counts.json').write_text(json.dumps(counts, indent=2) + '\n')
    print(json.dumps(counts, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['hagrid', 'mix'])
    parser.add_argument('root', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.phase == 'hagrid':
        sample_hagrid(args.root, args.output)
    else:
        mix(args.root, args.output)
