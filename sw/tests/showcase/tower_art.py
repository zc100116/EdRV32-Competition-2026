#!/usr/bin/env python3
"""tower_art.py — emit the actual straight ARGB8888 tower art for GEO host acceptance."""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools' / 'sw'))
from png2c import decode_png

assets = Path(__file__).resolve().parents[2] / 'apps/showcase/assets/tower'
with Path(sys.argv[1]).open('wb') as output:
    for material in ('wood', 'stone', 'ice', 'metal', 'rubber', 'glass'):
        for shape in ('square', 'plank', 'brick', 'triangle', 'arch', 'circle'):
            png = assets / f'block-{material}-{shape}.png'
            width, height, rgba = decode_png(png.read_bytes())
            output.write(struct.pack('<II', width, height))
            for offset in range(0, len(rgba), 4):
                r, g, b, a = rgba[offset:offset + 4]
                output.write(struct.pack('<I', a << 24 | r << 16 | g << 8 | b))
