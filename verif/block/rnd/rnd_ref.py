#!/usr/bin/env python3
# File: rnd_ref.py
# Spec: rnd 2.1–2.6, 6; rnd-testplan 4.
# Description: Independent integer renderer, descriptor codec and executable arithmetic selftests.
# Clock domain: host.
"""Byte-exact RND oracle. Colors are (alpha, red, green, blue), never premultiplied."""
import argparse
from dataclasses import dataclass
from math import isqrt
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import struct

BPP = (16, 32, 8, 4, 2, 1, 8)
Q = (0,) + tuple((255 * 65536 + a // 2) // a for a in range(1, 256))


def d(x):
    t = x + 128
    return (t + (t >> 8)) >> 8


def mix(a, foreground, background):
    return d(a * foreground + (255 - a) * background)


def e565(value):
    r, g, b = value >> 11, (value >> 5) & 63, value & 31
    return (255, (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def p565(color):
    _, r, g, b = color
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def argb(value):
    return tuple((value >> shift) & 255 for shift in (24, 16, 8, 0))


def pack_argb(color):
    return sum(channel << shift for channel, shift in zip(color, (24, 16, 8, 0)))


def over(source, sa, destination, fmt):
    """rnd 2.2: sa=0 preserves even nonzero RGB under zero destination alpha."""
    if sa == 0:
        return destination
    dest = e565(destination) if fmt == 0 else argb(destination)
    colors = tuple(source)
    if fmt == 0:
        return p565((255,) + tuple(mix(sa, s, b) for s, b in zip(colors, dest[1:])))
    oa = sa + d((255 - sa) * dest[0])
    if oa == 0:
        return 0
    ratio = (sa * Q[oa] + 32768) >> 16
    return pack_argb((oa,) + tuple(mix(ratio, s, b) for s, b in zip(colors, dest[1:])))


def coverage(width, height, radius, i, j):
    """rnd 2.3: isqrt is exact; antialiasing is horizontal only."""
    if not (0 <= i < width and 0 <= j < height):
        return 0
    radius = min(radius, min(width, height) // 2)
    jd = min(j, height - 1 - j)
    edge = 0
    if radius > 0 and jd < radius:
        dy = 16 * (radius - jd) - 8
        edge = 16 * radius - isqrt(256 * radius * radius - dy * dy)
    room = min(16 * i + 16 - edge, 16 * width - edge - 16 * i)
    return 0 if room <= 0 else 255 if room >= 16 else 16 * room


def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def xy(x, y):
    return (x & 65535) | ((y & 65535) << 16)


@dataclass(frozen=True)
class Command:
    op: int
    dst_fmt: int = 1
    src_fmt: int = 0
    flags: int = 0
    dst_base: int = 0x10000
    dst_stride: int = 132
    clip: tuple = (0, 0, 31, 23)
    rect: tuple = (2, 2, 20, 17)
    color: int = 0x9173cd
    opa: int = 128
    args: tuple = (0,) * 8

    def words(self):
        cx0, cy0, cx1, cy1 = self.clip
        x0, y0, x1, y1 = self.rect
        return [self.op | (self.dst_fmt << 8) | (self.src_fmt << 12) | (self.flags << 16),
                self.dst_base, self.dst_stride, xy(cx0, cy0), xy(cx1, cy1),
                xy(x0, y0), xy(x1, y1), self.color | (self.opa << 24),
                *(value & 0xffffffff for value in self.args)]

    def encode(self):
        return struct.pack('<16I', *self.words())

    @classmethod
    def decode(cls, data):
        w = struct.unpack('<16I', data)
        return cls(w[0] & 255, (w[0] >> 8) & 1, (w[0] >> 12) & 15, w[0] >> 16,
                   w[1], w[2] & 65535,
                   (w[3] & 4095, (w[3] >> 16) & 4095,
                    w[4] & 4095, (w[4] >> 16) & 4095),
                   (signed(w[5], 16), signed(w[5] >> 16, 16),
                    signed(w[6], 16), signed(w[6] >> 16, 16)),
                   w[7] & 0xffffff, w[7] >> 24, w[8:])

    def illegal(self):
        # rnd 6: these are the complete command-validation conditions.
        return (self.op not in range(1, 6)
                or (self.op == 3 and self.src_fmt not in (2, 3, 4, 5))
                or (self.op == 4 and self.src_fmt not in (0, 1, 6))
                or (self.op == 4 and ((self.flags >> 4) & 7) != 0)
                or (self.op == 5 and self.src_fmt != self.dst_fmt))


def fill(*, radius=0, grad_start=0, steps=(0, 0, 0, 0), **common):
    return Command(1, args=(radius, grad_start, *steps, 0, 0), **common)


def border(*, radius=0, width=1, sides=15, **common):
    return Command(2, args=(radius, width | (sides << 16), 0, 0, 0, 0, 0, 0), **common)


def glyph(*, src_base, src_stride, src_x=0, src_y=0, **common):
    return Command(3, args=(src_base, src_stride, xy(src_x, src_y), 0, 0, 0, 0, 0), **common)


def blit(*, src_base, src_stride, src_x=0, src_y=0, scale_x=65536, scale_y=65536,
         palette=0, key=0, rc_color=0, rc_opa=0, **common):
    return Command(4, args=(src_base, src_stride, xy(src_x, src_y), scale_x, scale_y,
                            palette, key, rc_color | (rc_opa << 24)), **common)


def copy(*, src_base, src_stride, src_x=0, src_y=0, **common):
    return Command(5, args=(src_base, src_stride, xy(src_x, src_y), 0, 0, 0, 0, 0), **common)


def load(memory, address, size):
    return int.from_bytes(memory[address:address + size], 'little')


def store(memory, address, size, value):
    memory[address:address + size] = value.to_bytes(size, 'little')


def raw_pixel(memory, base, stride, fmt, x, y):
    bits = BPP[fmt]
    offset = base + y * stride + x * bits // 8
    if bits >= 8:
        return load(memory, offset, bits // 8)
    return (memory[offset] >> (8 - bits - (x * bits % 8))) & ((1 << bits) - 1)


def source_pixel(memory, base, stride, fmt, x, y, palette, colorkey, key):
    value = raw_pixel(memory, base, stride, fmt, x, y)
    if fmt == 0:
        color = e565(value)
        return (0 if colorkey and value == key else 255,) + color[1:]
    if fmt == 1:
        return argb(value)
    return argb(load(memory, palette + 4 * value, 4))


def area(command):
    x0, y0, x1, y1 = command.rect
    if x1 < x0 or y1 < y0:
        return (0, 0, -1, -1)
    cx0, cy0, cx1, cy1 = command.clip
    return max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)


def execute_command(memory, command):
    """Render one legal command. Only retained v1 commands are implemented."""
    c = command
    ax0, ay0, ax1, ay1 = area(c)
    if ax1 < ax0 or ay1 < ay0:
        return 0
    x0, y0, x1, y1 = c.rect
    width, height = x1 - x0 + 1, y1 - y0 + 1
    w = c.args
    size = 2 << c.dst_fmt
    snapshot = {}
    if c.op == 5:
        # rnd 2.6 COPY: snapshot includes every source before the first destination store.
        for y in range(ay0, ay1 + 1):
            for x in range(ax0, ax1 + 1):
                snapshot[x, y] = raw_pixel(memory, w[0], w[1] & 65535, c.src_fmt,
                                          (w[2] & 65535) + x - x0,
                                          (w[2] >> 16) + y - y0)
    for y in range(ay0, ay1 + 1):
        for x in range(ax0, ax1 + 1):
            address = c.dst_base + y * c.dst_stride + x * size
            dest = load(memory, address, size)
            color = argb(c.color)[1:]
            sa = c.opa
            if c.op == 1:
                alpha = 255
                if c.flags & 1:
                    k = y - y0 if c.flags & 2 else x - x0
                    gradient = tuple(max(0, min(255, (start * 65536
                                     + k * signed(step, 32) + 32768) >> 16))
                                     for start, step in zip(argb(w[1]), w[2:6]))
                    alpha, *color = gradient
                sa = d(d(c.opa * alpha) * coverage(width, height, w[0] & 4095,
                                                    x - x0, y - y0))
            elif c.op == 2:
                radius = min(w[0] & 4095, min(width, height) // 2)
                bw, sides = w[1] & 4095, (w[1] >> 16) & 15
                ix0 = x0 + bw if sides & 4 else x0 - radius - 1
                iy0 = y0 + bw if sides & 1 else y0 - radius - 1
                ix1 = x1 - bw if sides & 8 else x1 + radius + 1
                iy1 = y1 - bw if sides & 2 else y1 + radius + 1
                outer = coverage(width, height, radius, x - x0, y - y0)
                inner = coverage(ix1 - ix0 + 1, iy1 - iy0 + 1, max(radius - bw, 0),
                                 x - ix0, y - iy0)
                sa = d(c.opa * d(outer * (255 - inner)))
            elif c.op == 3:
                value = raw_pixel(memory, w[0], w[1] & 65535, c.src_fmt,
                                  (w[2] & 65535) + x - x0, (w[2] >> 16) + y - y0)
                sa = d(c.opa * value * (255 // ((1 << BPP[c.src_fmt]) - 1)))
            elif c.op == 4:
                kx = x1 - x if c.flags & 1 else x - x0
                ky = y1 - y if c.flags & 2 else y - y0
                pixel = source_pixel(memory, w[0], w[1] & 65535, c.src_fmt,
                                     (w[2] & 65535) + ((kx * w[3]) >> 16),
                                     (w[2] >> 16) + ((ky * w[4]) >> 16), w[5],
                                     bool(c.flags & 4), w[6] & 65535)
                alpha, *color = pixel
                if c.flags & 8:
                    color = tuple(mix(w[7] >> 24, rc, s)
                                  for rc, s in zip(argb(w[7])[1:], color))
                sa = d(c.opa * alpha)
            elif c.op == 5:
                store(memory, address, size, snapshot[x, y])
                continue
            store(memory, address, size, over(color, sa, dest, c.dst_fmt))
    return (ax1 - ax0 + 1) * (ay1 - ay0 + 1)


@dataclass
class Result:
    completed: int = 0
    pixels: int = 0
    error: int = 0
    cur_desc: int = 0


def execute(memory, commands):
    result = Result()
    for index, command in enumerate(commands):
        result.cur_desc = index
        # Decode the wire representation so ignored/reserved bits follow rnd 2.5.
        command = Command.decode(command.encode())
        if command.illegal():
            result.error = 3
            return result
        result.pixels += execute_command(memory, command)
        result.completed += 1
    result.cur_desc = result.completed
    return result


def selftest():
    for x in range(65026):
        assert d(x) == (x + 127) // 255, ('d', x)
    assert Q[1] == 16711680 and Q[255] == 65536
    for a in range(1, 256):
        assert Q[a] == (255 * 65536 + a // 2) // a
    for value in range(65536):
        assert p565(e565(value)) == value
    for sa in range(256):
        for da in range(256):
            out = over((31, 141, 233), sa, (da << 24) | 0x93a26d, 1)
            if sa == 0:
                assert out == (da << 24) | 0x93a26d
            elif sa == 255:
                assert out == 0xff1f8de9
            elif da == 255:
                assert out == pack_argb((255,) + tuple(mix(sa, s, b)
                    for s, b in zip((31, 141, 233), (147, 162, 109))))
            else:
                oa = sa + (127 + (255 - sa) * da) // 255
                ratio = (sa * Q[oa] + 32768) // 65536
                assert out == pack_argb((oa,) + tuple((127 + ratio * s
                    + (255 - ratio) * b) // 255
                    for s, b in zip((31, 141, 233), (147, 162, 109))))
    assert over((1, 2, 3), 0, 0, 1) == 0  # oa=0, sa=0 intersection.
    assert over((100, 150, 200), 255, 0xffc86432, 1) == 0xff6496c8
    assert coverage(4, 4, 1, 0, 0) == 208
    assert coverage(4, 4, 2, 0, 0) == 80
    mask = bytearray((0xad,))
    for fmt, wanted in ((2, (173,)), (3, (10, 13)), (4, (2, 2, 3, 1)),
                        (5, (1, 0, 1, 0, 1, 1, 0, 1))):
        assert tuple(raw_pixel(mask, 0, 1, fmt, i, 0) for i in range(len(wanted))) == wanted
    for width in (1, 2, 7, 16):
        for height in (1, 2, 8, 17):
            for radius in (0, 1, 2, 7, 4095):
                for j in range(height):
                    for i in range(width):
                        cov = coverage(width, height, radius, i, j)
                        assert cov == coverage(width, height, radius, width - 1 - i, j)
                        assert cov == coverage(width, height, radius, i, height - 1 - j)
                        assert 0 <= cov <= 255
    # Codec and illegal-command truth table cover every OP/SRC_FMT/MODE encoding.
    for op in range(256):
        for fmt in range(16):
            for mode in range(8):
                cmd = Command(op, src_fmt=fmt, flags=mode << 4)
                decoded = Command.decode(cmd.encode())
                allowed = (op in (1, 2)
                           or op == 3 and fmt in (2, 3, 4, 5)
                           or op == 4 and fmt in (0, 1, 6) and mode == 0
                           or op == 5 and fmt == 1)
                assert decoded.illegal() != allowed
    print('PASS rnd_ref: d exhaustive=65026, RGB565=65536, over=65536, '
          'Q=255, coverage symmetry, legality=32768')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--selftest', action='store_true')
    parser.add_argument('--input', type=Path)
    parser.add_argument('--commands', type=Path, help='Packed 64-byte descriptors')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.selftest:
        selftest()
    else:
        memory = bytearray(args.input.read_bytes())
        data = args.commands.read_bytes()
        commands = [Command.decode(data[i:i + 64]) for i in range(0, len(data), 64)]
        result = execute(memory, commands)
        args.output.write_bytes(memory)
        print(result)


if __name__ == '__main__':
    main()
