#!/usr/bin/env python3
"""raw2png.py — showcase design §5: convert 1280×720 little endian RGB565 to PNG."""
import argparse
from pathlib import Path
import struct
import zlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('destination', type=Path)
args = parser.parse_args()
pixels = struct.unpack('<' + 'H' * (1280 * 720), args.source.read_bytes())
rows = bytearray()
for y in range(720):
    rows.append(0)
    for pixel in pixels[y * 1280:(y + 1) * 1280]:
        r, g, b = pixel >> 11, (pixel >> 5) & 63, pixel & 31
        rows.extend(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)))

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

args.destination.write_bytes(b'\x89PNG\r\n\x1a\n' +
    chunk(b'IHDR', struct.pack('>IIBBBBB', 1280, 720, 8, 2, 0, 0, 0)) +
    chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))
