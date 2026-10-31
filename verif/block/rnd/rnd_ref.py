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
import random
import sys

sys.dont_write_bytecode = True
import struct

BPP = (16, 32, 8, 4, 2, 1, 8, 4, 2, 1)
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


def over(source, sa, destination, fmt, mode=0):
    """rnd 2.2: sa=0 preserves even nonzero RGB under zero destination alpha."""
    if sa == 0:
        return destination
    dest = e565(destination) if fmt == 0 else argb(destination)
    colors = tuple(source)
    if mode == 1:
        colors = tuple(min(s + b, 255) for s, b in zip(colors, dest[1:]))
    elif mode == 2:
        colors = tuple(max(b - s, 0) for s, b in zip(colors, dest[1:]))
    elif mode == 3:
        colors = tuple(d(s * b) for s, b in zip(colors, dest[1:]))
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


def blur_line(values, radius, nearest):
    """rnd 2.4: prefix sums implement the specified sum, rounding once per pass."""
    size = len(values)
    prefix = [0]
    for value in values:
        prefix.append(prefix[-1] + value)
    multiplier = (65536 + radius) // (2 * radius + 1)
    result = []
    for i in range(size):
        lo, hi = i - radius, i + radius + 1
        total = prefix[min(hi, size)] - prefix[max(lo, 0)]
        if nearest:
            total += max(-lo, 0) * values[0] + max(hi - size, 0) * values[-1]
        result.append((total * multiplier + 32768) >> 16)
    return result


def blur_grid(grid, radius, nearest):
    horizontal = [blur_line(row, radius, nearest) for row in grid]
    return [list(row) for row in zip(*(blur_line(list(col), radius, nearest)
                                       for col in zip(*horizontal)))]


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
        return (self.op not in range(1, 14)
                or (self.op == 3 and self.src_fmt not in (2, 3, 4, 5))
                or (self.op in (4, 13) and self.src_fmt not in (0, 1, 6, 7, 8, 9))
                or (self.op in (4, 13) and ((self.flags >> 4) & 7) >= 4)
                or (self.op == 5 and self.src_fmt != self.dst_fmt)
                or (self.op == 8 and self.src_fmt not in (0, 1, 6, 7)))


def fill(*, radius=0, grad_start=0, steps=(0, 0, 0, 0), **common):
    return Command(1, args=(radius, grad_start, *steps, 0, 0), **common)


def border(*, radius=0, width=1, sides=15, **common):
    return Command(2, args=(radius, width | (sides << 16), 0, 0, 0, 0, 0, 0), **common)


def glyph(*, src_base, src_stride, src_x=0, src_y=0, **common):
    return Command(3, args=(src_base, src_stride, xy(src_x, src_y), 0, 0, 0, 0, 0), **common)


def blit(*, src_base, src_stride, src_x=0, src_y=0, scale_x=65536, scale_y=65536,
         palette=0, key=0, rc_color=0, rc_opa=0, clip_radius=0, **common):
    return Command(4, args=(src_base, src_stride, xy(src_x, src_y), scale_x, scale_y,
                            palette, key | (clip_radius << 16),
                            rc_color | (rc_opa << 24)), **common)


def copy(*, src_base, src_stride, src_x=0, src_y=0, **common):
    return Command(5, args=(src_base, src_stride, xy(src_x, src_y), 0, 0, 0, 0, 0), **common)


def box_shadow(*, radius=0, blur=0, temp_base, bg=(0, 0, 0, 0), bg_radius=0, **common):
    return Command(6, args=(radius, blur, temp_base, xy(*bg[:2]), xy(*bg[2:]),
                            bg_radius, 0, 0), **common)


def blur(*, radius=0, temp_base, **common):
    return Command(7, args=(radius, temp_base, 0, 0, 0, 0, 0, 0), **common)


def tilemap(*, tile_base, map_base, map_stride, map_x=0, map_y=0, palette=0,
            key=0, **common):
    return Command(8, args=(tile_base, map_base, map_stride, xy(map_x, map_y),
                            0, palette, key, 0), **common)


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
    if command.op == 6:
        radius = command.args[1] & 31
        x0, y0, x1, y1 = x0 - radius, y0 - radius, x1 + radius, y1 + radius
    cx0, cy0, cx1, cy1 = command.clip
    return max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)


def temp_region(command):
    ax0, ay0, ax1, ay1 = area(command)
    if ax1 < ax0 or ay1 < ay0:
        return (0, 0)
    if command.op == 6:
        x0, y0, x1, y1 = command.rect
        radius = command.args[1] & 31
        stride = ((x1 - x0 + 1 + 2 * radius + 31) // 32) * 32
        return command.args[2], 2 * stride * (y1 - y0 + 1 + 2 * radius)
    if command.op == 7:
        stride = (((ax1 - ax0 + 1) * 4 + 31) // 32) * 32
        return command.args[1], stride * (ay1 - ay0 + 1)
    return (0, 0)


def parameter_words(memory, base, count):
    return tuple(load(memory, base + 4 * k, 4) for k in range(count))


def rectangle_words(first, last):
    return (signed(first, 16), signed(first >> 16, 16),
            signed(last, 16), signed(last >> 16, 16))


def rectangle_coverage(rect, radius, x, y):
    x0, y0, x1, y1 = rect
    return coverage(x1 - x0 + 1, y1 - y0 + 1, radius, x - x0, y - y0)


def linear8(words, a, b):
    """Exact edge value multiplied by eight; no Q16 sub-sample truncation."""
    e0, ex, ey = (signed(v, 32) for v in words)
    return 8 * e0 + a * ex + b * ey


def circle_value(words, a, b):
    q0 = signed(words[0] | ((words[1] & 65535) << 32), 48)
    dx, dy = signed(words[2], 32), signed(words[3], 32)
    return q0 + a * (dx - 64) // 8 + b * (dy - 64) // 8 + a * a + b * b


def geometry_inside(c, p, a, b):
    if c.op == 9:
        values = [linear8(p[k:k + 3], a, b) for k in (0, 3, 6)]
        return all(v >= 0 if c.flags & (2 << k) else v > 0
                   for k, v in enumerate(values))
    if c.op == 10:
        t, n = linear8(p[:3], a, b), linear8(p[3:6], a, b)
        body = 0 <= t <= 8 * p[6] and abs(n) <= 8 * p[7]
        return (body or bool(c.flags & 2) and circle_value(p[8:12], a - 1, b - 1) <= 0
                or bool(c.flags & 4) and circle_value(p[12:16], a - 1, b - 1) <= 0)
    ring = (circle_value(p[:4], a - 1, b - 1) <= 0
            and (bool(c.flags & 32) or circle_value(p[4:8], a - 1, b - 1) > 0))
    if c.flags & 16:
        return ring
    b0, b1 = linear8(p[16:19], a, b) >= 0, linear8(p[19:22], a, b) >= 0
    body = ring and ((b0 or b1) if c.flags & 8 else (b0 and b1))
    return (body or bool(c.flags & 2) and circle_value(p[8:12], a - 1, b - 1) <= 0
            or bool(c.flags & 4) and circle_value(p[12:16], a - 1, b - 1) <= 0)


def geometry_coverage(c, p, x, y):
    offsets = (1, 3, 5, 7) if c.flags & 1 else (4,)
    count = sum(geometry_inside(c, p, 8 * (x - c.rect[0]) + i,
                               8 * (y - c.rect[1]) + j)
                for j in offsets for i in offsets)
    return (255 * count + len(offsets) ** 2 // 2) // len(offsets) ** 2


def affine_sample(memory, c, p, x, y):
    w = c.args
    u0, v0, ux, vx, uy, vy = (signed(v, 32) for v in p[:6])
    u = u0 + (x - c.rect[0]) * ux + (y - c.rect[1]) * uy
    v = v0 + (x - c.rect[0]) * vx + (y - c.rect[1]) * vy
    sw, sh = w[2] & 65535, w[2] >> 16

    def tap(i, j):
        if not (0 <= i < sw and 0 <= j < sh):
            return (0, 0, 0, 0)
        return source_pixel(memory, w[0], w[1] & 65535, c.src_fmt, i, j,
                            w[5], bool(c.flags & 4), w[6] & 65535)

    if not c.flags & 1:
        return tap(u // 65536, v // 65536)
    s, t = u - 32768, v - 32768
    i, j = s // 65536, t // 65536
    f, g = (s % 65536) >> 8, (t % 65536) >> 8
    weights = ((256 - f) * (256 - g), f * (256 - g), (256 - f) * g, f * g)
    taps = [tap(i, j), tap(i + 1, j), tap(i, j + 1), tap(i + 1, j + 1)]
    alpha = (sum(wt * color[0] for wt, color in zip(weights, taps)) + 32768) >> 16
    if alpha == 0:
        return (0, 0, 0, 0)
    premul = tuple((sum(wt * d(color[0] * color[k]) for wt, color in zip(weights, taps))
                    + 32768) >> 16 for k in (1, 2, 3))
    return (alpha,) + tuple(min(255, (v * Q[alpha] + 32768) >> 16) for v in premul)


def execute_command(memory, command):
    """Render one legal command. Temporary bytes deliberately have no oracle value."""
    c = command
    ax0, ay0, ax1, ay1 = area(c)
    if ax1 < ax0 or ay1 < ay0:
        return 0
    x0, y0, x1, y1 = c.rect
    width, height = x1 - x0 + 1, y1 - y0 + 1
    w = c.args
    size = 2 << c.dst_fmt
    p = ()
    if c.op in (9, 10, 11):
        p = parameter_words(memory, w[0], 32)
    elif c.op == 13:
        p = parameter_words(memory, w[3], 16)
    elif c.op == 4 and c.flags & 128:
        p = parameter_words(memory, w[5], 16)
    snapshot = {}
    shadow = None
    blurred = None
    if c.op == 5:
        # rnd 2.6 COPY: snapshot includes every source before the first destination store.
        for y in range(ay0, ay1 + 1):
            for x in range(ax0, ax1 + 1):
                snapshot[x, y] = raw_pixel(memory, w[0], w[1] & 65535, c.src_fmt,
                                          (w[2] & 65535) + x - x0,
                                          (w[2] >> 16) + y - y0)
    if c.op == 6:
        radius = w[1] & 31
        shadow = blur_grid([[coverage(width, height, w[0] & 4095, i - radius, j - radius)
                             for i in range(width + 2 * radius)]
                            for j in range(height + 2 * radius)], radius, False)
    if c.op == 7:
        original = [[(e565 if c.dst_fmt == 0 else argb)(
            load(memory, c.dst_base + y * c.dst_stride + x * size, size))
                     for x in range(ax0, ax1 + 1)] for y in range(ay0, ay1 + 1)]
        channels = [blur_grid([[pixel[k] for pixel in row] for row in original],
                              w[0] & 31, True) for k in range(4)]
        blurred = [[tuple(channels[k][y][x] for k in range(4))
                    for x in range(ax1 - ax0 + 1)] for y in range(ay1 - ay0 + 1)]
    for y in range(ay0, ay1 + 1):
        for x in range(ax0, ax1 + 1):
            address = c.dst_base + y * c.dst_stride + x * size
            dest = load(memory, address, size)
            color = argb(c.color)[1:]
            sa = c.opa
            mode = 0
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
                                     (w[2] >> 16) + ((ky * w[4]) >> 16), p[0] if p else w[5],
                                     bool(c.flags & 4), w[6] & 65535)
                alpha, *color = pixel
                if c.flags & 8:
                    color = tuple(mix(w[7] >> 24, rc, s)
                                  for rc, s in zip(argb(w[7])[1:], color))
                cov = rectangle_coverage(rectangle_words(p[1], p[2]),
                                         (w[6] >> 16) & 4095, x, y) if p and (
                                             (w[6] >> 16) & 4095) else 255
                sa = d(d(c.opa * alpha) * cov)
                mode = (c.flags >> 4) & 7
            elif c.op == 5:
                store(memory, address, size, snapshot[x, y])
                continue
            elif c.op == 6:
                radius = w[1] & 31
                mask = shadow[y - y0 + radius][x - x0 + radius]
                if c.flags & 1:
                    bg = rectangle_coverage(rectangle_words(w[3], w[4]), w[5] & 4095, x, y)
                    mask = d(mask * (255 - bg))
                sa = d(c.opa * mask)
            elif c.op == 7:
                pixel = blurred[y - ay0][x - ax0]
                store(memory, address, size, p565(pixel) if c.dst_fmt == 0 else pack_argb(pixel))
                continue
            elif c.op == 8:
                tile_size = 16 if c.flags & 1 else 8
                mx, my = (w[3] & 65535) + x - x0, (w[3] >> 16) + y - y0
                entry = load(memory, w[1] + (my // tile_size) * (w[2] & 65535)
                             + 2 * (mx // tile_size), 2)
                tx, ty = mx % tile_size, my % tile_size
                if entry & 4096:
                    tx = tile_size - 1 - tx
                if entry & 8192:
                    ty = tile_size - 1 - ty
                stride = tile_size * BPP[c.src_fmt] // 8
                base = w[0] + (entry & 4095) * stride * tile_size
                pixel = source_pixel(memory, base, stride, c.src_fmt, tx, ty, w[5],
                                     bool(c.flags & 4), w[6] & 65535)
                alpha, *color = pixel
                sa = d(c.opa * alpha)
            elif c.op in (9, 10, 11):
                cov = geometry_coverage(c, p, x, y)
                alpha = 255
                if c.op == 9 and c.flags & 64:
                    k = y - y0 if c.flags & 128 else x - x0
                    alpha, *color = tuple(max(0, min(255, (start * 65536
                        + k * signed(step, 32) + 32768) >> 16))
                        for start, step in zip(argb(p[9]), p[10:14]))
                sa = d(d(c.opa * alpha) * cov)
            elif c.op == 12:
                rect = rectangle_words(w[1], w[2])
                inside = rect[0] <= x <= rect[2] and rect[1] <= y <= rect[3]
                cov = rectangle_coverage(rect, w[0] & 4095, x, y) if inside else (
                    255 if c.flags & 1 else 0)
                alpha = d((dest >> 24) * cov)
                store(memory, address, size, (alpha << 24) | (dest & 0xffffff) if alpha else 0)
                continue
            elif c.op == 13:
                alpha, *color = affine_sample(memory, c, p, x, y)
                if c.flags & 8:
                    color = tuple(mix(w[7] >> 24, rc, s)
                                  for rc, s in zip(argb(w[7])[1:], color))
                cov = rectangle_coverage(rectangle_words(p[6], p[7]), w[4] & 4095, x, y
                                         ) if c.flags & 128 and w[4] & 4095 else 255
                sa = d(d(c.opa * alpha) * cov)
                mode = (c.flags >> 4) & 7
            store(memory, address, size, over(color, sa, dest, c.dst_fmt, mode))
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
    for mode, wanted in enumerate((0xff6496c8, 0xfffffafa, 0xff640000, 0xff4e3b27)):
        assert over((100, 150, 200), 255, 0xffc86432, 1, mode) == wanted
    assert coverage(4, 4, 1, 0, 0) == 208
    assert coverage(4, 4, 2, 0, 0) == 80
    mask = bytearray((0xad,))
    for fmt, wanted in ((2, (173,)), (3, (10, 13)), (4, (2, 2, 3, 1)),
                        (5, (1, 0, 1, 0, 1, 1, 0, 1))):
        assert tuple(raw_pixel(mask, 0, 1, fmt, i, 0) for i in range(len(wanted))) == wanted
    rng = random.Random(18)
    for radius in range(32):
        n = 2 * radius + 1
        multiplier = (65536 + radius) // n
        # Every possible sum, including maximum, independently checks the stated upper bound.
        for total in range(255 * n + 1):
            value = (total * multiplier + 32768) >> 16
            assert 0 <= value <= 255
            assert abs(value * n - total) <= 0.6 * n
        values = [rng.randrange(256) for _ in range(7)]
        for nearest in (False, True):
            expected = []
            for i in range(len(values)):
                samples = [values[max(0, min(len(values) - 1, j))] if nearest
                           else values[j] if 0 <= j < len(values) else 0
                           for j in range(i - radius, i + radius + 1)]
                expected.append((sum(samples) * multiplier + 32768) >> 16)
            assert blur_line(values, radius, nearest) == expected
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
                allowed = (op in (1, 2, 6, 7, 9, 10, 11, 12)
                           or op == 3 and fmt in (2, 3, 4, 5)
                           or op in (4, 13) and fmt in (0, 1, 6, 7, 8, 9) and mode < 4
                           or op == 5 and fmt == 1
                           or op == 8 and fmt in (0, 1, 6, 7))
                assert decoded.illegal() != allowed
    print('PASS rnd_ref: d exhaustive=65026, RGB565=65536, over=65536, '
          'Q=255, blur all sums/R=0..31, coverage symmetry, legality=32768')


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
