#!/usr/bin/env python3
"""quickdraw_synth.py — T-DOODLE-DATA: synthesize camera-sized doodle detections.

Use recognized QuickDraw drawings with disjoint key_id train/validation splits.
Clock domain: not applicable (offline training-data tool).
"""

import json
from pathlib import Path
import tarfile

import cv2
import numpy as np


NAMES = (
    'cat', 'dog', 'fish', 'bird', 'rabbit', 'butterfly', 'sun', 'moon', 'star',
    'cloud', 'lightning', 'rainbow', 'tree', 'flower', 'house', 'car', 'airplane',
    'sailboat', 'apple', 'smiley face',
)
WIDTH, HEIGHT = 1280, 720
SOURCE = Path.home() / '.local/share/edrv32/quickdraw'
OUTPUT = Path('build/doodle')


def load_drawings(rng):
    """Sort recognized key_ids before seeded selection, independent of source order."""
    drawings = {'train': [], 'val': []}
    for class_id, name in enumerate(NAMES):
        path = SOURCE / f'{name}.ndjson'
        with path.open() as source:
            keys = sorted(
                {record['key_id'] for line in source
                 if (record := json.loads(line))['recognized']}, key=int,
            )
        selected = rng.permutation(len(keys))[:3300]
        split_by_key = {
            keys[index]: 'train' if position < 3000 else 'val'
            for position, index in enumerate(selected)
        }
        with path.open() as source:
            for line in source:
                record = json.loads(line)
                if record['recognized'] and record['key_id'] in split_by_key:
                    split = split_by_key.pop(record['key_id'])
                    strokes = [np.array(stroke, dtype=np.float64).T
                               for stroke in record['drawing']]
                    drawings[split].append((class_id, strokes))
        print(f'Loaded {name}: 3000 train, 300 val', flush=True)
    return drawings


def render(strokes, rng):
    angle = np.deg2rad(rng.uniform(-15, 15))
    rotation = np.array([[np.cos(angle), -np.sin(angle)],
                         [np.sin(angle), np.cos(angle)]])
    rotated = [stroke @ rotation.T for stroke in strokes]
    points = np.concatenate(rotated)
    low = points.min(axis=0)
    extent = points.max(axis=0) - low
    thickness = int(rng.integers(3, 13))
    # Every drawing fits a 640x360 cell, including stroke thickness after rotation.
    longest = min(400, (360 - thickness - 2) * extent.max() / extent[1]
                  + thickness + 2) if extent[1] else 400
    # Raster endpoints can shorten the floating-point span by up to two pixels.
    size = rng.uniform(82, longest)
    scale = (size - thickness - 2) / extent.max()
    transformed = [np.rint((stroke - low) * scale + thickness / 2 + 1).astype(np.int32)
                   for stroke in rotated]
    dimensions = np.ceil(extent * scale + thickness + 3).astype(int)
    mask = np.zeros((dimensions[1], dimensions[0]), dtype=np.uint8)
    for stroke in transformed:
        cv2.polylines(mask, [stroke], False, 255, thickness, cv2.LINE_8)
        for point in (stroke[0], stroke[-1]):
            cv2.circle(mask, tuple(point), thickness // 2, 255, -1)
    x, y, width, height = cv2.boundingRect(mask)
    return mask[y:y + height, x:x + width]


def background(rng):
    canvas = np.full((HEIGHT, WIDTH), rng.integers(235, 256), dtype=np.uint8)
    count = int(rng.integers(50, 151))
    canvas[rng.integers(0, HEIGHT, count), rng.integers(0, WIDTH, count)] = 0
    for _ in range(int(rng.integers(0, 4))):
        if rng.integers(0, 2):
            center = (int(rng.integers(WIDTH)), int(rng.integers(HEIGHT)))
            cv2.ellipse(canvas, center, (int(rng.integers(2, 9)),
                        int(rng.integers(2, 9))), float(rng.uniform(0, 180)), 0, 360, 0, -1)
        else:
            x = 0 if rng.integers(0, 2) else WIDTH - 1
            y = int(rng.integers(HEIGHT))
            cv2.line(canvas, (x, y), (x, min(HEIGHT - 1, y + int(rng.integers(20, 100)))),
                     0, int(rng.integers(1, 5)))
    return canvas


def synthesize(split, drawings, rng, sample_count):
    root = OUTPUT / 'yolo'
    for kind in ('images', 'labels'):
        (root / kind / split).mkdir(parents=True, exist_ok=True)
    order = rng.permutation(len(drawings))
    counts = np.zeros(len(NAMES), dtype=int)
    cursor = 0
    image_count = 0
    image_bytes = 0
    while cursor < len(order):
        count = min(int(rng.integers(1, 5)), len(order) - cursor)
        cells = rng.permutation(4)[:count]
        canvas = background(rng)
        labels = []
        boxes = []
        for offset, cell in enumerate(cells):
            class_id, strokes = drawings[order[cursor + offset]]
            mask = render(strokes, rng)
            height, width = mask.shape
            x = int(cell % 2) * 640 + int(rng.integers(0, 640 - width + 1))
            y = int(cell // 2) * 360 + int(rng.integers(0, 360 - height + 1))
            region = canvas[y:y + height, x:x + width]
            region[mask != 0] = 0
            labels.append(f'{class_id} {(x + width / 2) / WIDTH:.8f} '
                          f'{(y + height / 2) / HEIGHT:.8f} '
                          f'{width / WIDTH:.8f} {height / HEIGHT:.8f}\n')
            boxes.append((class_id, x, y, width, height))
            counts[class_id] += 1
        png_ok, png = cv2.imencode('.png', canvas, [cv2.IMWRITE_PNG_COMPRESSION, 3])
        jpg_ok, jpg = cv2.imencode('.jpg', canvas, [cv2.IMWRITE_JPEG_QUALITY, 95])
        if not png_ok or not jpg_ok:
            raise RuntimeError(f'Image encoding failed: {split}/{image_count:06d}')
        extension, data = ('.png', png) if png.size <= jpg.size else ('.jpg', jpg)
        stem = f'{image_count:06d}'
        (root / 'images' / split / (stem + extension)).write_bytes(data.tobytes())
        (root / 'labels' / split / (stem + '.txt')).write_text(''.join(labels))
        image_bytes += data.size
        if image_count < sample_count:
            preview = cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR)
            for class_id, x, y, width, height in boxes:
                cv2.rectangle(preview, (x, y), (x + width - 1, y + height - 1),
                              (0, 150, 0), 2)
                cv2.putText(preview, NAMES[class_id], (x, max(16, y - 5)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 100, 0), 2)
            if not cv2.imwrite(str(OUTPUT / 'samples' / f'{split}-{stem}.png'), preview):
                raise RuntimeError(f'Sample encoding failed: {split}/{stem}')
        cursor += count
        image_count += 1
    print(f'{split}: {image_count} images, {image_bytes} image bytes', flush=True)
    for name, count in zip(NAMES, counts):
        print(f'  {name}: {count}', flush=True)


def main():
    rng = np.random.default_rng(0)
    drawings = load_drawings(rng)
    (OUTPUT / 'samples').mkdir(parents=True, exist_ok=True)
    for split in ('train', 'val'):
        synthesize(split, drawings[split], rng, sample_count=4)
    # Relative to the YAML file, so the archive remains usable after upload/extraction.
    config = 'train: images/train\nval: images/val\nnames:\n'
    config += ''.join(f'  {index}: {name}\n' for index, name in enumerate(NAMES))
    (OUTPUT / 'yolo/doodle.yaml').write_text(config)
    archive = OUTPUT / 'doodle-yolo.tar'
    with tarfile.open(archive, 'w') as tar:
        tar.add(OUTPUT / 'yolo', arcname='yolo')
    print(f'{archive}: {archive.stat().st_size} bytes', flush=True)


if __name__ == '__main__':
    main()
