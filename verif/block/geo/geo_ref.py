#!/usr/bin/env python3
# File: geo_ref.py
# Spec: geo 2.1–2.6, 5.2; pix 2.1.
# Description: Independent integer RGB565 affine reference and hand-calculated selftest.
# Clock domain: host.
"""Bit-exact GEO reference; memory and descriptors use little-endian byte addresses."""
from dataclasses import dataclass
import math
import struct
import sys

BW, BH, PW, PH = 32, 16, 80, 80
ONE = 1 << 16


def signed32(value):
    value &= 0xffffffff
    return value - (1 << 32) if value & (1 << 31) else value


@dataclass(frozen=True)
class Descriptor:
    src: int
    src_stride: int
    sw: int
    sh: int
    dst: int
    dst_stride: int
    rx: int
    ry: int
    rw: int
    rh: int
    bg: int = 0
    a: int = ONE
    b: int = 0
    tx: int = 0
    c: int = 0
    d: int = ONE
    ty: int = 0

    @classmethod
    def decode(cls, words):
        return cls(words[0] & 0xfffff000, words[1] & 0xffe0,
                   words[2] & 0xfff, (words[2] >> 16) & 0xfff,
                   words[3] & 0xfffff000, words[4] & 0xffe0,
                   words[5] & 0xff0, (words[5] >> 16) & 0xfff,
                   words[6] & 0xffe, (words[6] >> 16) & 0xfff,
                   words[7] & 0xffff, *(signed32(w) for w in words[8:14]))

    def words(self):
        return [self.src, self.src_stride, self.sw | (self.sh << 16),
                self.dst, self.dst_stride, self.rx | (self.ry << 16),
                self.rw | (self.rh << 16), self.bg,
                *(v & 0xffffffff for v in
                  (self.a, self.b, self.tx, self.c, self.d, self.ty)), 0, 0]


def range_ok(desc):
    return (abs(desc.a) * (BW - 1) + abs(desc.b) * (BH - 1) <= (PW - 2) * ONE
            and abs(desc.c) * (BW - 1) + abs(desc.d) * (BH - 1) <= (PH - 2) * ONE)


def expand(pixel):
    r, g, b = (pixel >> 11) & 31, (pixel >> 5) & 63, pixel & 31
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)


def interpolate(pixels, fx, fy):
    weights = ((256 - fx) * (256 - fy), fx * (256 - fy),
               (256 - fx) * fy, fx * fy)
    colors = [expand(p) for p in pixels]
    r, g, b = ((sum(p[channel] * w for p, w in zip(colors, weights)) + 32768) >> 16
               for channel in range(3))
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def pixel_at(memory, desc, u, v):
    # geo 2.1: arithmetic shift floors negative coordinates; only bits [15:8] are used.
    x = signed32(desc.a * u + desc.b * v + desc.tx)
    y = signed32(desc.c * u + desc.d * v + desc.ty)
    x0, y0 = x >> 16, y >> 16
    pixels = []
    for j, i in ((y0, x0), (y0, x0 + 1), (y0 + 1, x0), (y0 + 1, x0 + 1)):
        if 0 <= i < desc.sw and 0 <= j < desc.sh:
            address = desc.src + j * desc.src_stride + i * 2
            pixels.append(memory[address] | (memory[address + 1] << 8))
        else:
            pixels.append(desc.bg)
    return interpolate(pixels, (x >> 8) & 255, (y >> 8) & 255)


def execute(memory, words):
    """Apply one decoded descriptor in place, returning the specified ERR_CODE."""
    desc = Descriptor.decode(words)
    if not range_ok(desc):
        return 3
    for v in range(desc.rh):
        for u in range(desc.rw):
            value = pixel_at(memory, desc, u, v)
            address = desc.dst + (desc.ry + v) * desc.dst_stride + 2 * (desc.rx + u)
            struct.pack_into('<H', memory, address, value)
    return 0


def matrix(angle, sx=1.0, sy=None, source_center=(0, 0), output_center=(0, 0)):
    """Stimulus helper: positive angle rotates the output clockwise, scale is src/dst."""
    sy = sx if sy is None else sy
    sine, cosine = math.sin(math.radians(angle)), math.cos(math.radians(angle))
    a, b, c, d = (round(v * ONE) for v in
                  (sx * cosine, sx * sine, -sy * sine, sy * cosine))
    u, v = output_center
    tx = round(source_center[0] * ONE - a * u - b * v)
    ty = round(source_center[1] * ONE - c * u - d * v)
    return dict(a=a, b=b, tx=tx, c=c, d=d, ty=ty)


def selftest():
    def equal(label, expected, actual):
        if expected != actual:
            raise AssertionError(f'FAIL {label}: desc=0 coord=(0,0) '
                                 f'expected={expected!r} actual={actual!r} time=host')

    memory = bytearray(0x4000)
    for j, row in enumerate(((0xf800, 0x07e0), (0x001f, 0xffff))):
        for i, value in enumerate(row):
            struct.pack_into('<H', memory, j * 32 + i * 2, value)
    desc = Descriptor(0, 32, 2, 2, 0x1000, 32, 0, 0, 2, 2, bg=0x1234)
    equal('identity execute', 0, execute(memory, desc.words()))
    equal('identity rows', (0xf800, 0x07e0, 0x001f, 0xffff),
          tuple(struct.unpack_from('<H', memory, 0x1000 + j * 32 + i * 2)[0]
                for j in range(2) for i in range(2)))
    rotated = Descriptor(**{**desc.__dict__, 'a': 0, 'b': ONE, 'c': -ONE,
                            'd': 0, 'ty': ONE})
    equal('90 degrees', (0x001f, 0xf800, 0xffff, 0x07e0),
          tuple(pixel_at(memory, rotated, u, v) for v in range(2) for u in range(2)))
    equal('quarter blend rounds RGB888 then truncates', 0x8410,
          interpolate((0xf800, 0x07e0, 0x001f, 0xffff), 128, 128))
    outside = Descriptor(**{**desc.__dict__, 'tx': -2 * ONE, 'ty': -2 * ONE})
    equal('all samples BG', 0x1234, pixel_at(memory, outside, 0, 0))
    partial = Descriptor(**{**desc.__dict__, 'bg': 0, 'tx': -ONE // 2})
    equal('negative floor and partial BG', 0x8000, pixel_at(memory, partial, 0, 0))
    equal('negative one LSB floors to -1', 0xf800,
          pixel_at(memory, Descriptor(**{**partial.__dict__, 'tx': -1}), 0, 0))
    equal('low eight fractional bits ignored', 0xf800,
          pixel_at(memory, Descriptor(**{**desc.__dict__, 'tx': 255}), 0, 0))
    equal('fx=255', 0x07e0, interpolate((0xf800, 0x07e0, 0, 0), 255, 0))
    equal('RGB565 expansion', (255, 255, 255), expand(0xffff))
    # 31*A <= 78*65536: adjacent Q16.16 integers straddle the limit.
    boundary = (78 * ONE) // 31
    equal('range lower', True, range_ok(Descriptor(**{**desc.__dict__, 'a': boundary})))
    equal('range upper', False,
          range_ok(Descriptor(**{**desc.__dict__, 'a': boundary + 1})))
    equal('range y lower', True,
          range_ok(Descriptor(**{**desc.__dict__, 'c': boundary, 'd': 0})))
    equal('range y upper', False,
          range_ok(Descriptor(**{**desc.__dict__, 'c': boundary + 1, 'd': 0})))
    equal('range exact equality accepted', True,
          range_ok(Descriptor(**{**desc.__dict__, 'a': -131073, 'b': 69903})))
    equal('range exact equality plus one LSB rejected', False,
          range_ok(Descriptor(**{**desc.__dict__, 'a': -131073, 'b': 69904})))
    before = bytes(memory)
    equal('range error', 3,
          execute(memory, Descriptor(**{**desc.__dict__, 'a': boundary + 1}).words()))
    equal('range error no write', before, bytes(memory))
    dirty = desc.words()
    dirty[0] |= 0xfff
    dirty[1] |= 0xffff001f
    dirty[5] |= 0xf000f00f
    dirty[6] |= 0xf000f001
    dirty[14:16] = [0xdeadbeef, 0x87654321]
    equal('ignored bits', desc, Descriptor.decode(dirty))
    memory[0x1000:0x1100] = b'\xa5' * 256
    rectangle = Descriptor(**{**desc.__dict__, 'dst_stride': 64, 'rx': 31, 'ry': 1,
                              'rw': 3, 'rh': 1})
    equal('rectangle execute', 0, execute(memory, rectangle.words()))
    expected_row = bytearray(b'\xa5' * 256)
    # RX=31 decodes to 16, RW=3 decodes to 2; row 1, columns 16 and 17 only.
    expected_row[96:100] = bytes.fromhex('00f8e007')
    equal('rectangle masks and unchanged outside', bytes(expected_row),
          bytes(memory[0x1000:0x1100]))
    for field in ('rw', 'rh'):
        before = bytes(memory)
        equal(f'empty {field}', 0,
              execute(memory, Descriptor(**{**desc.__dict__, field: 0}).words()))
        equal(f'empty {field} unchanged', before, bytes(memory))
    print('PASS GEO reference selftest (hand-calculated, no DUT result)')


if __name__ == '__main__':
    if sys.argv[1:] != ['--selftest']:
        raise SystemExit('usage: geo_ref.py --selftest')
    selftest()
