#!/usr/bin/env python3
# File: blend_ref.py
# Spec: DISP v0.3 2.3-2.7; testplan 4, DS-14 through DS-16.
# Description: Independent surface/window/blend and per-layer late-beat model.
# Clock domain: host model of clk_pix; standard library only.
"""Pixel-accurate DISP reference and deterministic DS-15 frame generator."""
import argparse
from collections import deque
from dataclasses import dataclass
from pathlib import Path
import random

WIDTH = 1280
HEIGHT = 720
ALPHAS = (0, 1, 127, 128, 254, 255)
OPACITIES = (0, 1, 128, 255, 73, 219)


def divide255(value):
    temporary = value + 128
    return (temporary + (temporary >> 8)) >> 8


def expand565(value):
    red, green, blue = value >> 11, (value >> 5) & 63, value & 31
    return ((red << 3) | (red >> 2), (green << 2) | (green >> 4),
            (blue << 3) | (blue >> 2))


def blend(background, foreground, opacity):
    alpha = divide255((foreground >> 24) * opacity)
    channels = ((foreground >> 16) & 255, (foreground >> 8) & 255, foreground & 255)
    return tuple(divide255(alpha * front + (255 - alpha) * back)
                    for front, back in zip(channels, background))


def pattern565(tag, x, y, seed=1):
    word = ((x + 1) * 0x45d9f3b ^ (y + 1) * 0x119de1f3 ^
            seed * 0x10204081 ^ tag * 0x17234567) & 0xffffffff
    return (word ^ (word >> 16)) & 65535


def pattern_argb(tag, x, y, seed=1):
    word = ((x + 1) * 0x1b873593 ^ (y + 1) * 0x5bd1e995 ^
            seed * 0x01010101 ^ tag * 0x1234567) & 0xffffffff
    alpha = ALPHAS[x % 8] if x % 8 < 6 else (word >> 24)
    return alpha << 24 | (word & 0xffffff)


@dataclass(frozen=True)
class Frame:
    l0_base: int = 0x80000000
    l0_stride: int = 4096
    scroll_x: int = 0
    scroll_y: int = 0
    l0_enable: bool = True
    l1_base: int = 0x81000000
    l1_stride: int = 5120
    x: int = 0
    y: int = 0
    width: int = WIDTH
    height: int = HEIGHT
    opacity: int = 255
    l1_enable: bool = False

    def descriptors(self):
        for row in range(HEIGHT):
            if self.l0_enable:
                yield (0, row, self.l0_base + (self.scroll_y + row) * self.l0_stride +
                        32 * (self.scroll_x // 16), 2592 if self.scroll_x % 16 else 2560)
            if self.l1_enable and self.y <= row < self.y + self.height:
                yield (1, row, self.l1_base + (row - self.y) * self.l1_stride, 4 * self.width)

    def pixel(self, x, y, read565, read_argb, missing0=False, missing1=False, scan=True):
        if not scan:
            return (0, 0, 0)
        background = (0, 0, 0)
        if self.l0_enable and not missing0:
            address = self.l0_base + (self.scroll_y + y) * self.l0_stride
            background = expand565(read565(address + 2 * (self.scroll_x + x)))
        if (self.l1_enable and not missing1 and self.x <= x < self.x + self.width and
                self.y <= y < self.y + self.height):
            address = self.l1_base + (y - self.y) * self.l1_stride + 4 * (x - self.x)
            return blend(background, read_argb(address), self.opacity)
        return background


class LayerDebt:
    """Arrivals are ordered; missed demands create debt, including across frames."""
    def __init__(self):
        self.queue = deque()
        self.debt = 0
        self.missed = 0
        self.discarded = []

    def arrive(self, beat):
        self.queue.append(beat)
        self.repay()

    def repay(self):
        while self.debt and self.queue:
            self.discarded.append(self.queue.popleft())
            self.debt -= 1

    def demand(self):
        self.repay()
        if self.queue:
            return self.queue.popleft()
        self.debt += 1
        self.missed += 1
        return None


def self_test():
    for value in range(65026):
        assert divide255(value) == (value + 127) // 255, value
    rng = random.Random(5181)
    for alpha in (*ALPHAS, *(rng.randrange(256) for _ in range(32))):
        for opacity in OPACITIES:
            background = tuple(rng.randrange(256) for _ in range(3))
            front = tuple(rng.randrange(256) for _ in range(3))
            argb = alpha << 24 | front[0] << 16 | front[1] << 8 | front[2]
            effective = (alpha * opacity + 127) // 255
            expected = tuple((effective * f + (255 - effective) * b + 127) // 255
                                for f, b in zip(front, background))
            assert blend(background, argb, opacity) == expected
    for scroll in (*range(16), 16, 31, 48):
        frame = Frame(scroll_x=scroll, scroll_y=3, l1_enable=True, x=1272, y=719,
                        width=8, height=1)
        desc = list(frame.descriptors())
        assert len(desc) == 721
        assert desc[0] == (0, 0, 0x80000000 + 3 * 4096 + 32 * (scroll // 16),
                            2592 if scroll % 16 else 2560)
        assert desc[-1] == (1, 719, 0x81000000, 32)
        addresses = []
        def read565(address):
            addresses.append(address)
            return 0xf800
        assert frame.pixel(1271, 719, read565, lambda _: 0xffffffff) == (255, 0, 0)
        assert addresses[-1] == frame.l0_base + 722 * 4096 + 2 * (scroll + 1271)
        assert frame.pixel(1272, 719, read565, lambda _: 0xff123456) == (18, 52, 86)
        assert frame.pixel(1272, 719, read565, lambda _: 0xff123456,
                            missing1=True) == (255, 0, 0)
        assert frame.pixel(1271, 719, read565, lambda _: 0, missing0=True) == (0, 0, 0)
        assert frame.pixel(0, 0, read565, lambda _: 0, scan=False) == (0, 0, 0)
    # DS-18: changing the view stride must not change stored RAM contents.
    frame = Frame(l0_stride=4128, scroll_x=31, scroll_y=3, l1_stride=5152,
                    x=8, y=1, width=1272, height=719, opacity=128, l1_enable=True)
    def fixed565(address):
        offset = address - frame.l0_base
        return pattern565(0, (offset % 4096) // 2, offset // 4096)
    def fixed_argb(address):
        offset = address - frame.l1_base
        return pattern_argb(0, (offset % 5120) // 4, offset // 5120)
    assert frame.pixel(19, 2, fixed565, fixed_argb) == blend(
        expand565(pattern565(0, 130, 5)), pattern_argb(0, 19, 1), 128)
    layers = [LayerDebt(), LayerDebt()]
    assert layers[0].demand() is None
    assert layers[0].demand() is None
    layers[1].arrive('L1-current')
    assert layers[1].demand() == 'L1-current'
    # Late arrivals during a disabled frame still repay the preceding frame's debt.
    layers[0].arrive('L0-late0')
    layers[0].arrive('L0-late1')
    layers[0].arrive('L0-next-frame')
    assert layers[0].demand() == 'L0-next-frame'
    assert layers[0].discarded == ['L0-late0', 'L0-late1']
    assert layers[0].debt == layers[1].debt == 0
    assert layers[0].missed == 2 and layers[1].missed == 0
    print('PASS blend_ref: exhaustive d(x) 0..65025, blend, windows, descriptors, layer debt')


def generate(path, seed=1):
    with path.open('w') as output:
        for opacity in OPACITIES:
            frame = Frame(opacity=opacity, l1_enable=True)
            def read565(address):
                offset = address - frame.l0_base
                return pattern565(0, (offset % 4096) // 2, offset // 4096, seed)
            def read_argb(address):
                offset = address - frame.l1_base
                return pattern_argb(0, (offset % 5120) // 4, offset // 5120, seed)
            for y in range(HEIGHT):
                for x in range(WIDTH):
                    red, green, blue = frame.pixel(x, y, read565, read_argb)
                    output.write(f'{red:02x}{green:02x}{blue:02x}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, nargs='?')
    args = parser.parse_args()
    self_test()
    if args.output:
        generate(args.output)


if __name__ == '__main__':
    main()
