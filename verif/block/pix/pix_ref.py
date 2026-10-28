#!/usr/bin/env python3
# File: pix_ref.py
# Spec: PIX 2.1-2.5; PIX testplan 4.
# Description: Independent integer RGB565 frame reference and hand-calculated selftest.
# Clock domain: host.
"""Bit-exact PIX reference. No DUT implementation is imported or inspected."""
from pathlib import Path
import argparse


def clamp(value):
    return max(0, min(255, value))


def expand(pixel):
    r, g, b = pixel >> 11, (pixel >> 5) & 63, pixel & 31
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def pack(rgb):
    r, g, b = rgb
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def gray(rgb):
    r, g, b = rgb
    return (77 * r + 150 * g + 29 * b + 128) >> 8


def point1(rgb, cfg, contrast, brightness, tables):
    if cfg & 1:
        rgb = tuple(clamp(((c - 128) * contrast >> 8) + 128 + brightness) for c in rgb)
    if cfg & 2:
        rgb = tuple(tables[(cfg >> 2) & 1][c] for c in rgb)
    return rgb


def window_op(window, op):
    """Nine RGB888 neighbours in raster order, including explicit zero padding."""
    if op in (0, 7):
        return window[4]
    if op == 1:
        return tuple((sum(p[c] for p in window) + 4) // 9 for c in range(3))
    if op == 2:
        weights = (1, 2, 1, 2, 4, 2, 1, 2, 1)
        return tuple((sum(p[c] * w for p, w in zip(window, weights)) + 8) >> 4
                     for c in range(3))
    if op == 3:
        return tuple(clamp(5 * window[4][c] - sum(window[n][c] for n in (1, 3, 5, 7)))
                     for c in range(3))
    y = [gray(p) for p in window]
    if op == 4:
        gx = -y[0] + y[2] - 2 * y[3] + 2 * y[5] - y[6] + y[8]
        gy = -y[0] - 2 * y[1] - y[2] + y[6] + 2 * y[7] + y[8]
        result = min(abs(gx) + abs(gy), 255)
    elif op == 5:
        result = min(y)
    else:  # All OP encodings are defined by PIX 2.4.
        result = max(y)
    return (result,) * 3


def stage(image, width, height, op):
    if op in (0, 7):
        return image
    result = []
    for y in range(height):
        for x in range(width):
            window = [image[ny * width + nx] if 0 <= nx < width and 0 <= ny < height
                      else (0, 0, 0)
                      for ny in range(y - 1, y + 2) for nx in range(x - 1, x + 2)]
            result.append(window_op(window, op))
    return result


def point2(rgb, cfg, threshold):
    if cfg & (1 << 16):
        rgb = (gray(rgb),) * 3
    if cfg & (1 << 17):
        rgb = (255 if gray(rgb) >= threshold else 0,) * 3
    if cfg & (1 << 18):
        rgb = tuple(255 - c for c in rgb)
    return rgb


def process(pixels, width, height, enable, cfg, bc, threshold, tables):
    if not enable:
        return list(pixels)
    contrast = bc & 511
    brightness = (bc >> 16) & 511
    if brightness & 256:
        brightness -= 512
    image = [point1(expand(p), cfg, contrast, brightness, tables) for p in pixels]
    image = stage(image, width, height, (cfg >> 4) & 7)
    image = stage(image, width, height, (cfg >> 8) & 7)
    return [pack(point2(p, cfg, threshold)) for p in image]


def gamma_tables():
    # Both banks are fully initialized via APB before any frame uses Gamma.
    return [list(range(256)), [255 - c for c in range(256)]]


def generate(directory):
    directory = Path(directory)
    lines = (directory / 'scenario.txt').read_text().splitlines()
    for index in range(len(lines)):
        fields = list(map(int, (directory / f'cfg{index}.txt').read_text().split()))
        width, height, enable, cfg, bc, threshold, sent = fields
        if sent < width * height // 2:
            continue  # PIX testplan 4: no reference output for an incomplete frame.
        pixels = [int(p, 16) for p in (directory / f'in{index}.hex').read_text().split()]
        expected = process(pixels, width, height, enable, cfg, bc, threshold, gamma_tables())
        (directory / f'out{index}.hex').write_text(''.join(f'{p:04x}\n' for p in expected))


def selftest():
    # Values below are hand calculations, independent of process()/stage().
    assert expand(0xf800) == (255, 0, 0)
    assert expand(0x07e0) == (0, 255, 0)
    assert expand(0x001f) == (0, 0, 255)
    assert expand(0x8c51) == (140, 138, 140)
    assert pack((7, 3, 7)) == 0
    assert pack((255, 255, 255)) == 0xffff
    assert [gray(c) for c in ((255, 0, 0), (0, 255, 0), (0, 0, 255))] == [77, 149, 29]
    assert gray(expand(0x7c10)) == 128
    tables = gamma_tables()
    assert point1((0, 128, 255), 1, 511, -256, tables) == (0, 0, 125)
    assert point1((0, 128, 255), 1, 511, 255, tables) == (127, 255, 255)
    assert point1((0, 127, 255), 1, 0, -1, tables) == (127, 127, 127)
    # Negative arithmetic shift: (-1 * 128) >> 8 = -1, not zero.
    assert point1((127, 128, 129), 1, 128, 0, tables) == (127, 128, 128)
    assert point1((0, 128, 255), 7, 256, 0, tables) == (255, 127, 0)
    black = (0, 0, 0)
    white = (255, 255, 255)
    corner = [black] * 9
    corner[4] = white
    assert window_op(corner, 1) == (28, 28, 28)  # (255 + 4) // 9.
    assert window_op(corner, 2) == (64, 64, 64)  # (4*255 + 8) >> 4.
    assert window_op(corner, 3) == white
    assert window_op(corner, 5) == black
    assert window_op(corner, 6) == white
    assert window_op([white] * 9, 3) == white
    dark_center = [white] * 9
    dark_center[4] = black
    assert window_op(dark_center, 3) == black
    edge = [black, black, white] * 3
    assert window_op(edge, 4) == white  # Gx=1020, Gy=0, saturates.
    ramp = [(c, c, c) for c in range(9)]
    assert window_op(ramp, 4) == (32, 32, 32)  # Gx=8, Gy=24.
    assert stage([white, white], 2, 1, 1) == [(57, 57, 57)] * 2
    assert stage([white, white], 2, 1, 2) == [(96, 96, 96)] * 2
    assert stage([white] * 9, 3, 3, 1) == [
        (113, 113, 113), (170, 170, 170), (113, 113, 113),
        (170, 170, 170), white, (170, 170, 170),
        (113, 113, 113), (170, 170, 170), (113, 113, 113)]
    assert point2((128, 128, 128), 1 << 17, 128) == white
    assert point2(black, 1 << 17, 0) == white
    assert point2((254, 254, 254), 1 << 17, 255) == black
    assert point2(white, 7 << 16, 255) == black
    assert process([0xf800, 0x001f], 2, 1, 0, 0x77777, 0, 0, tables) == [0xf800, 0x001f]
    assert process([0xf800, 0x001f], 2, 1, 1, 0, 256, 128, tables) == [0xf800, 0x001f]
    assert process([0xf800, 0x001f], 2, 1, 1, 0x770, 256, 128, tables) == [0xf800, 0x001f]
    # Full chain: BC->127, bank1->128, mean->28, Gaussian->11, BIN/INV.
    cfg = 7 | (1 << 4) | (2 << 8) | (7 << 16)
    bc = 511 << 16  # Contrast 0, brightness -1.
    assert process([0xffff] * 2, 2, 1, 1, cfg, bc, 12, tables) == [0xffff] * 2
    assert process([0xffff] * 2, 2, 1, 1, cfg, bc, 11, tables) == [0] * 2
    for pixel in range(65536):
        assert pack(expand(pixel)) == pixel
    print('PASS PIX reference selftest (hand calculations, saturation, zero-padding, RGB565)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('selftest', 'generate'))
    parser.add_argument('directory', nargs='?')
    args = parser.parse_args()
    if args.mode == 'selftest':
        selftest()
    else:
        generate(args.directory)
