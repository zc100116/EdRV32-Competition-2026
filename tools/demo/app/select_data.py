#!/usr/bin/env python3
"""select_data.py — R5-13: stream permitted COCO metadata and local HaGRID labels.

Only source metadata is written; dataset images remain outside version control.
Clock: host tool. Run from repository root.
"""
import io
import json
from pathlib import Path
import zipfile

DATA = Path.home() / '.local/share/edrv32/npu'
BUILD = Path('build/demo-app')


def objects(stream, key):
    """Read one top-level array without materializing the full annotation document."""
    prefix = ''
    marker = '"' + key + '"'
    while marker not in prefix:
        prefix = prefix[-len(marker):] + stream.read(65536)
    rest = prefix.split(marker, 1)[1]
    while '[' not in rest:
        rest += stream.read(65536)
    chunk = rest.split('[', 1)[1]
    depth = 0
    quoted = escaped = False
    value = []
    while chunk:
        for char in chunk:
            if depth == 0:
                if char == ']':
                    return
                if char != '{':
                    continue
            value.append(char)
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char == '{':
                depth += 1
            elif char == '}':
                depth -= 1
                if depth == 0:
                    yield json.loads(''.join(value))
                    value = []
        chunk = stream.read(65536)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    candidates = {}
    annotations = {}
    with zipfile.ZipFile(DATA / 'annotations_trainval2017.zip') as archive:
        name = 'annotations/instances_train2017.json'
        with archive.open(name) as binary:
            for row in objects(io.TextIOWrapper(binary), 'images'):
                path = DATA / 'coco128/images/train2017' / row['file_name']
                if row['license'] in (4, 5, 7, 8) and path.exists():
                    candidates[row['id']] = row | {'path': str(path)}
        with archive.open(name) as binary:
            for row in objects(io.TextIOWrapper(binary), 'annotations'):
                if row['image_id'] in candidates and not row['iscrowd']:
                    annotations.setdefault(row['image_id'], []).append(row)
        with archive.open(name) as binary:
            categories = list(objects(io.TextIOWrapper(binary), 'categories'))
        with archive.open(name) as binary:
            licenses = list(objects(io.TextIOWrapper(binary), 'licenses'))
    rows = []
    for id, image in candidates.items():
        image['annotations'] = annotations.get(id, [])
        if any(a['area'] >= image['width']*image['height']*.02 for a in image['annotations']):
            rows.append(image)
    with zipfile.ZipFile(DATA / 'annotations_trainval2017.zip') as archive:
        validation = json.loads(archive.read('annotations/instances_val2017.json'))
    by_image = {}
    for annotation in validation['annotations']:
        if not annotation['iscrowd']:
            by_image.setdefault(annotation['image_id'], []).append(annotation)
    for image in validation['images']:
        path = DATA / 'val2017' / image['file_name']
        if image['license'] in (4, 5, 7, 8) and path.exists():
            image = image | {'path': str(path), 'annotations': by_image.get(image['id'], [])}
            if any(a['area'] >= image['width']*image['height']*.02
                   for a in image['annotations']):
                rows.append(image)
    (BUILD / 'coco-candidates.json').write_text(json.dumps(dict(
        images=rows, categories=categories, licenses=licenses), indent=2))
    print('permitted COCO candidates:', len(rows))
    hands = []
    root = DATA / 'hagrid-val600'
    for label in sorted((root / 'labels/val').glob('*.txt')):
        fields = label.read_text().splitlines()
        if len(fields) == 1:
            cls = int(fields[0].split()[0])
            if cls < 13:
                hands.append(dict(id=label.stem, cls=cls,
                                  path=str(root / 'images/val' / (label.stem+'.jpg'))))
    (BUILD / 'hagrid-candidates.json').write_text(json.dumps(hands, indent=2))
    print('HaGRID candidates:', len(hands))


if __name__ == '__main__':
    main()
