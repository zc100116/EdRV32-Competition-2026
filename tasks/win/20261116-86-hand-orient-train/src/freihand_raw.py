#!/usr/bin/env python3
"""freihand_raw.py: card 86, original FreiHAND images with ignored class labels.
Clock domain: not applicable (offline dataset assembly).
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import numpy as np
from data_common import hand_box, write_records, yolo_line
from freihand_composite import prepare


def convert(source, output, margins):
    counts = Counter()
    groups = prepare(source, counts, margins)
    records = []
    for split, samples in groups.items():
        images = output / 'images' / split
        labels = output / 'labels' / split
        images.mkdir(parents=True)
        labels.mkdir(parents=True)
        for sample in samples:
            name = f"{sample['source_id']:08d}"
            image = images / (name + '.jpg')
            os.link(source / 'training/rgb' / (name + '.jpg'), image)
            points = np.array(sample['points'])
            box = hand_box(points, margins)
            # YOLO boxes describe the visible image rectangle at the image boundary.
            box = np.clip(box, 0, 224)
            (labels / (name + '.txt')).write_text(yolo_line(14, points, box, 224, 224) + '\n')
            records.append(dict(**sample, image=str(image), split=split,
                                box=box.tolist(), visible=[True] * 21))
            counts[f'{split}/images'] += 1
    write_records(output, records, counts)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('margins', type=Path)
    args = parser.parse_args()
    convert(args.source, args.output, json.loads(args.margins.read_text()))
