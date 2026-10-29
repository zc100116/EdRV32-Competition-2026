#!/usr/bin/env python3
# File: crosscheck.py
# Spec: vin 2.8; Task B2-1c reference crosscheck against tools/npu/input_pack.py.
# Description: Feed the identical expanded RGB565 image to the integer model and NPU packer.
# Clock domain: host.
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/npu'))
sys.path.insert(0, str(ROOT / 'third_party/ultralytics'))
import cv2
import numpy as np
import torch
from input_pack import pack
from reference import expand, image, process


def main():
    out = ROOT / 'build/vin_ch2_crosscheck'
    out.mkdir(parents=True, exist_ok=True)
    pixels = image(0)
    rgb = np.array([expand(p) for p in pixels], dtype=np.uint8).reshape(720, 1280, 3)
    path = out / 'source.png'
    if not cv2.imwrite(str(path), rgb[:, :, ::-1]):
        raise RuntimeError(f'cannot write {path}')
    expected = process(pixels)
    actual = pack(path)
    assert len(actual) == len(expected), f'bytes expected={len(expected)} actual={len(actual)}'
    differences = [(i, a, b) for i, (a, b) in enumerate(zip(expected, actual)) if a != b]
    with (out / 'differences.tsv').open('w') as stream:
        stream.write('offset\ty\tx\tchannel\tinteger\tnpu\tdelta\n')
        for i, a, b in differences:
            stream.write(f'{i}\t{i // 2560}\t{i % 2560 // 4}\t{i % 4}\t{a}\t{b}\t{b-a}\n')
    (out / 'integer.bin').write_bytes(expected)
    (out / 'npu.bin').write_bytes(actual)
    print(f'Python={sys.version.split()[0]} OpenCV={cv2.__version__} '
          f'NumPy={np.__version__} torch={torch.__version__}')
    print(f'bytes={len(expected)} differences={len(differences)} '
          f'max_abs_delta={max((abs(a-b) for _, a, b in differences), default=0)}')
    for i, a, b in differences[:16]:
        print(f'offset={i} y={i//2560} x={i%2560//4} channel={i%4} integer={a} npu={b}')
    print(f'All differing locations: {out / "differences.tsv"}')


if __name__ == '__main__':
    main()
