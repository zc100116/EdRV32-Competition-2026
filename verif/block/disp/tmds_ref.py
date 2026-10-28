#!/usr/bin/env python3
# File: tmds_ref.py
# Spec: DISP 2.1-2.3; DVI 1.0 Figure 3-5.
# Description: Emit one complete 720p DVI frame with independent running disparity.
# Clock domain: host model of clk_pix.
"""Reference: https://glenwing.github.io/docs/DVI-1.0.pdf, Figure 3-5."""
import argparse
from pathlib import Path

CONTROL = (0b1101010100, 0b0010101011, 0b0101010100, 0b1010101011)


def encode(value, disparity):
    """Return a ten-bit symbol and the new signed running disparity."""
    xnor = value.bit_count() > 4 or (value.bit_count() == 4 and not value & 1)
    bits = [value & 1]
    for index in range(1, 8):
        bits.append(bits[-1] ^ ((value >> index) & 1) ^ xnor)
    word = sum(bit << index for index, bit in enumerate(bits))
    flag = int(not xnor)
    balance = 2 * word.bit_count() - 8
    if disparity == 0 or balance == 0:
        invert = not flag
    else:
        invert = (disparity > 0) == (balance > 0)
    symbol = (int(invert) << 9) | (flag << 8) | (word ^ (255 if invert else 0))
    return symbol, disparity + 2 * symbol.bit_count() - 10


def pixel565(tag, x, y):
    red = 1 + (x + y + tag * 7) % 31
    green = (y * 3 + x // 7 + tag * 13) % 64
    blue = (x * 3 + y * 5 + tag * 11) % 32
    return red << 11 | green << 5 | blue


def rgb888(value):
    red = value >> 11
    green = (value >> 5) & 63
    blue = value & 31
    return ((red << 3) | (red >> 2), (green << 2) | (green >> 4),
            (blue << 3) | (blue >> 2))


def generate(path):
    disparity = [0, 0, 0]
    with path.open('w') as output:
        for y in range(750):
            for x in range(1650):
                if y < 720 and x < 1280:
                    channels = rgb888(pixel565(0, x, y))[::-1]
                    symbols = []
                    for lane, value in enumerate(channels):
                        symbol, disparity[lane] = encode(value, disparity[lane])
                        symbols.append(symbol)
                else:
                    hs = 1390 <= x < 1430
                    sync_line = (y + int(x >= 1390)) % 750
                    vs = 725 <= sync_line < 730
                    symbols = [CONTROL[int(vs) * 2 + int(hs)], CONTROL[0], CONTROL[0]]
                    disparity = [0, 0, 0]
                output.write(f'{symbols[0] | symbols[1] << 10 | symbols[2] << 20:08x}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    generate(args.output)


if __name__ == '__main__':
    main()
