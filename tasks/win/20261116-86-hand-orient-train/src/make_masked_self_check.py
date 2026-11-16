#!/usr/bin/env python3
"""make_masked_self_check.py: supplement 2, small real-image class-mask fixture.
Each training image has a normal copy and a class-14 copy for loss verification.
Clock domain: not applicable (offline test fixture).
"""
import os
from pathlib import Path
import sys
import yaml

hagrid = Path(sys.argv[1])
output = Path(sys.argv[2])
for split, count in [('train', 32), ('val', 8)]:
    images = output / 'images' / split
    labels = output / 'labels' / split
    images.mkdir(parents=True)
    labels.mkdir(parents=True)
    for image in sorted((hagrid / 'images' / split).glob('*.jpg'))[:count]:
        original = (hagrid / 'labels' / split / (image.stem + '.txt')).read_text()
        versions = ['known', 'ignored'] if split == 'train' else ['known']
        for version in versions:
            name = version + '_' + image.name
            os.link(image, images / name)
            content = original
            if version == 'ignored':
                content = '\n'.join('14 ' + line.split(' ', 1)[1]
                                    for line in original.splitlines()) + '\n'
            (labels / (Path(name).stem + '.txt')).write_text(content)
config = yaml.safe_load((hagrid / 'hagrid.yaml').read_text())
config.update(path=str(output), train='images/train', val='images/val')
(output / 'self-check.yaml').write_text(yaml.safe_dump(config, sort_keys=False))
print('self-check train 64 (32 known + 32 ignored), val 8; synthetic ignore flags only')
