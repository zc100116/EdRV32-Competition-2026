#!/usr/bin/env python3
# File: reference.py
# Spec: vin 2.8; vin-testplan VI-19 through VI-23.
# Description: Independent integer RGB565 to INT8_C4 model and directed selftests.
# Clock domain: host, independent of RTL.
from fractions import Fraction
from pathlib import Path


def expand(pixel):
    r = (pixel >> 11) & 31
    g = (pixel >> 5) & 63
    b = pixel & 31
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def quantize(channel):
    return (254 * channel + 255) // 510


def block(pixels):
    rgb = [expand(pixel) for pixel in pixels]
    return bytes([quantize((sum(p[c] for p in rgb) + 2) >> 2) for c in range(3)] + [0])


def process(pixels):
    """Spec 2.8: fixed 1280x720 source, 640x384 output, DDR byte order R,G,B,0."""
    padding = bytes((57, 57, 57, 0)) * (640 * 12)
    result = bytearray(padding)
    for y in range(0, 720, 2):
        for x in range(0, 1280, 2):
            i = y * 1280 + x
            result.extend(block((pixels[i], pixels[i + 1],
                                 pixels[i + 1280], pixels[i + 1281])))
    result.extend(padding)
    return bytes(result)


def image(variant, width=1280, height=720):
    # Variant zero changes every source pixel; averaging cannot be replaced by decimation.
    if variant == 0:
        return [(0x9b61 ^ (x * 73) ^ (y * 137)) & 65535
                for y in range(height) for x in range(width)]
    if variant == 1:
        return [((x & 31) << 11) | ((y & 63) << 5) | ((x + y) & 31)
                for y in range(height) for x in range(width)]
    colors = (0, 0xffff, 0xf800, 0x07e0, 0x001f, 0x8410, 0x0821, 0xffdf)
    return [colors[((x // 2) + (y // 2)) % len(colors)]
            for y in range(height) for x in range(width)]


def selftest():
    for c in range(256):
        expected = round(Fraction(c * 127, 255))
        actual = quantize(c)
        assert actual == expected, f'q c={c} expected={expected} actual={actual}'
    for v in range(32):
        expected = v * 8 + v // 4
        actual = expand((v << 11) | v)
        assert actual == (expected, 0, expected), (v, actual, expected)
    for v in range(64):
        expected = v * 4 + v // 16
        actual = expand(v << 5)
        assert actual == (0, expected, 0), (v, actual, expected)
    cases = [((0, 0, 0, 0), bytes((0, 0, 0, 0))),
             ((65535,) * 4, bytes((127, 127, 127, 0))),
             ((0xf800,) * 4, bytes((127, 0, 0, 0))),
             ((0x07e0,) * 4, bytes((0, 127, 0, 0))),
             ((0x001f,) * 4, bytes((0, 0, 127, 0))),
             ((0, 0, 65535, 65535), bytes((64, 64, 64, 0))),
             ((0, 0, 0, 65535), bytes((32, 32, 32, 0))),
             # Half-integer averages where truncation would change the quantized byte.
             ((0, 0, 0x6000, 0x6000), bytes((25, 0, 0, 0))),
             ((0, 0, 0x0600, 0x0600), bytes((0, 49, 0, 0))),
             ((0, 0, 0x000c, 0x000c), bytes((0, 0, 25, 0))),
             # Expanded green sum=8: (8+2)>>2=2, quantized to 1.
             ((0, 0, 0x20, 0x20), bytes((0, 1, 0, 0)))]
    for pixels, expected in cases:
        actual = block(pixels)
        assert actual == expected, f'block={pixels} expected={expected} actual={actual}'
    actual = process([0xf800] * (1280 * 720))
    row = bytes((127, 0, 0, 0)) * 640
    pad = bytes((57, 57, 57, 0)) * 640
    assert len(actual) == 384 * 2560, f'expected=983040 actual={len(actual)}'
    for y in range(384):
        expected = pad if y < 12 or y >= 372 else row
        got = actual[y * 2560:(y + 1) * 2560]
        assert got == expected, f'row={y} expected={expected[:4]} actual={got[:4]}'
    print('PASS CH2 reference: expansion, all 256 quantizers, average, C4, 384 row boundaries')


def generate(out: Path, full: bool):
    out.mkdir(parents=True, exist_ok=True)
    (out / 'small.hex').write_text(''.join(f'{p:04x}\n' for p in image(0, 64, 8)))
    for variant in range(3 if full else 0):
        pixels = image(variant)
        (out / f'in{variant}.hex').write_text(''.join(f'{p:04x}\n' for p in pixels))
        packed = process(pixels)
        (out / f'out{variant}.hex').write_text(
            ''.join(f'{int.from_bytes(packed[i:i + 4], "little"):08x}\n'
                    for i in range(0, len(packed), 4)))
