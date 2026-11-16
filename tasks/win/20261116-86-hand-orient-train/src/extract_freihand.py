#!/usr/bin/env python3
"""extract_freihand.py: card 86 revised step 2, extract green-screen samples only.
Clock domain: not applicable (local selective ZIP extraction).
"""
from collections import Counter
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
output = Path(sys.argv[2])
counts = Counter()
with zipfile.ZipFile(archive) as source:
    for item in source.infolist():
        path = Path(item.filename)
        kind = None
        if path.parent.as_posix() == 'training/rgb' and int(path.stem) < 32560:
            kind = 'rgb'
        elif path.parent.as_posix() == 'training/mask':
            kind = 'mask'
        elif path.name.startswith('training_') and path.suffix == '.json':
            kind = 'json'
        if kind is not None:
            source.extract(item, output)
            counts[kind] += 1
            counts['bytes'] += item.file_size
print(dict(counts), flush=True)
