#!/usr/bin/env python3
# File: vectors.py
# Spec: geo-testplan GE-01–GE-13, 4, 6.
# Description: Deterministic directed/random stimuli and independent expected Surface images.
# Clock domain: host.
from dataclasses import replace
from pathlib import Path
import random
import struct

from geo_ref import Descriptor, ONE, execute, matrix

DESC_BASE = 0x1000
SRC_BASE = 0x10000
DST_BASE = 0x900000
MEM_BYTES = 32 * 1024 * 1024


def selections(tier):
    """Tuples are (testplan number, variant, seed); regress full also selects smoke."""
    if tier == 'perf':
        return [(12, v, 1) for v in (1, 2)]
    if tier == 'full':
        return ([(6, angle, 1) for angle in range(0, 360, 15) if angle % 90 != 0]
                + [(10, v, 1) for v in ('descriptor', 'source', 'write')]
                + [(13, 'random', seed) for seed in range(1, 11)])
    cases = [(1, v, 1) for v in ('identity', 'translate')]
    cases += [(2, v, 1) for v in (0, 90, 180, 270, 15, 45, -30)]
    cases += [(3, v, 1) for v in ('up1.5', 'up3', 'up8', 'down1.25', 'down2',
                                  'nonuniform', 'mirror_x', 'mirror_y', 'shear')]
    cases += [(4, v, 1) for v in ('partial', 'outside', 'one', 'zero_w', 'zero_h',
                                  'zero_both', 'frac0', 'frac255', 'negative_lsb')]
    cases += [(5, v, 1) for v in ('x0', 'x16', 'x1264', 'zero_w', 'zero_h',
                                  'tail34', 'ignored')]
    cases += [(6, v, 1) for v in (0, 90, 180, 270)]
    cases += [(6, v, 1) for v in ('down2.5', 'shear', 'below_x', 'above_x',
                                  'below_y', 'above_y', 'equal_x', 'equal_y')]
    cases += [(7, 'chain', 1), (8, 'clean', 1), (8, 'dirty', 1)]
    cases += [(9, v, 1) for v in ('descriptor', 'source', 'write')]
    cases += [(11, 'registers', 1)]
    return cases


def generate(directory, number, variant, seed):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0x6e0000 + number * 100 + seed)
    desc = Descriptor(SRC_BASE, 128, 64, 32, DST_BASE, 256, 0, 0, 64, 32, bg=0x39e7)
    descriptors = [desc]
    surfaces = [(DST_BASE, 256, 64)]
    mode = number
    error = 0
    injection = 0
    abort = 0
    latency = 3
    stall = 35
    bandwidth = 0
    bdelay = 3
    limit = 0
    dirty = number == 8 and variant == 'dirty'
    if number == 1 and variant == 'translate':
        descriptors = [replace(desc, tx=-3 * ONE, ty=2 * ONE)]
    elif number in (2, 3):
        desc = replace(desc, sh=48, rh=48)
        transform = matrix(variant if number == 2 else 0,
                           source_center=(31.5, 23.5), output_center=(31.5, 23.5))
        if number == 3:
            scales = {'up1.5': 1 / 1.5, 'up3': 1 / 3, 'up8': 1 / 8,
                      'down1.25': 1.25, 'down2': 2}
            if variant in scales:
                transform = matrix(0, scales[variant], source_center=(31.5, 23.5),
                                   output_center=(31.5, 23.5))
            elif variant == 'nonuniform':
                transform = matrix(15, 2, 0.5)
            elif variant == 'mirror_x':
                transform = dict(a=-ONE, tx=63 * ONE)
            elif variant == 'mirror_y':
                transform = dict(d=-ONE, ty=47 * ONE)
            else:
                transform = dict(b=ONE // 2, c=-ONE // 4)
        descriptors = [replace(desc, **transform)]
    elif number == 4:
        changes = {
            'partial': dict(tx=-ONE // 2, ty=-ONE // 2),
            'outside': dict(tx=-100 * ONE, ty=100 * ONE),
            'one': dict(sw=1, sh=1, tx=-ONE // 2, ty=-ONE // 2),
            'zero_w': dict(sw=0), 'zero_h': dict(sh=0),
            'zero_both': dict(sw=0, sh=0), 'frac0': dict(tx=ONE, ty=ONE),
            'frac255': dict(tx=0xff00, ty=0xff00),
            'negative_lsb': dict(tx=-1, ty=-1),
        }
        descriptors = [replace(desc, **changes[variant])]
    elif number == 5:
        desc = replace(desc, dst_stride=2560)
        changes = {'x0': dict(rx=0), 'x16': dict(rx=16),
                   'x1264': dict(rx=1264, rw=16), 'zero_w': dict(rw=0),
                   'zero_h': dict(rh=0), 'tail34': dict(rw=34),
                   'ignored': dict(rx=16, rw=34)}
        descriptors = [replace(desc, **changes[variant])]
        surfaces = [(DST_BASE, 2560, 64)]
        dirty = variant == 'ignored'
    elif number == 6:
        if isinstance(variant, int):
            desc = replace(desc, **matrix(variant, 2))
        elif variant == 'down2.5':
            desc = replace(desc, **matrix(45, 2.5))
            error = 3
        elif variant == 'shear':
            desc = replace(desc, b=4 * ONE)
            error = 3
        elif variant == 'equal_x':
            desc = replace(desc, a=-131073, b=69903)
        elif variant == 'equal_y':
            desc = replace(desc, c=131073, d=-69903)
        else:
            boundary = (78 * ONE) // 31
            upper = variant.startswith('above')
            desc = replace(desc, **{('a' if variant.endswith('x') else 'c'):
                                    boundary + int(upper)})
            if variant.endswith('y'):
                desc = replace(desc, d=0)
            error = 3 if upper else 0
        descriptors = [desc]
        if error:
            descriptors += [replace(desc, dst=DST_BASE + 0x200000, a=ONE, b=0, c=0)]
            surfaces += [(DST_BASE + 0x200000, 256, 64)]
    elif number == 7:
        descriptors = [replace(desc, dst=DST_BASE + i * 0x200000,
                               src=SRC_BASE if i == 0 else DST_BASE + (i - 1) * 0x200000,
                               src_stride=128 if i == 0 else 256,
                               tx=0 if i == 0 else ONE // 2)
                       for i in range(3)]
        surfaces = [(d.dst, 256, 64) for d in descriptors]
        latency = 20
        bdelay = 20
    elif number == 9:
        injection = {'descriptor': 1, 'source': 2, 'write': 3}[variant]
        error = 2 if injection == 3 else 1
        descriptors += [replace(desc, dst=DST_BASE + 0x200000)]
        surfaces += [(DST_BASE + 0x200000, 256, 64)]
    elif number == 10:
        abort = {'descriptor': 1, 'source': 2, 'write': 3}[variant]
        latency = 80
        bdelay = 200
    elif number == 11:
        latency = 80
    elif number == 12:
        sw, sh = (1280, 720) if variant == 1 else (2560, 1440)
        descriptors = [replace(desc, sw=sw, sh=sh, src_stride=sw * 2,
                               dst_stride=2560, rw=1280, rh=720,
                               **matrix(45, variant,
                                        source_center=((sw - 1) / 2, (sh - 1) / 2),
                                        output_center=(639.5, 359.5)))]
        surfaces = [(DST_BASE, 2560, 720)]
        latency, stall, bandwidth = 40, 0, 1
        limit = 16700000 if variant == 1 else 33000000  # ns; PERF0 / 125 MHz.
    elif number == 13:
        descriptors = []
        surfaces = []
        # Ten seeds contain 4 descriptors each; cycle stimulus families without filtering.
        for index in range(4):
            sw, sh = rng.randint(1, 256), rng.randint(1, 256)
            rw, rh = rng.randrange(1, 97) * 2, rng.randint(1, 96)
            rx, ry = 16 * rng.randrange(0, 5), rng.randrange(0, 9)
            sx = rng.choice((0.125, 1 / 3, 2 / 3, 1.0, 1.25, 2.0))
            transform = matrix(rng.uniform(-180, 180), sx,
                               source_center=((sw - 1) / 2, (sh - 1) / 2),
                               output_center=((rw - 1) / 2, (rh - 1) / 2))
            family = (seed + index) % 4
            if family == 1:
                transform = dict(a=-ONE, tx=(sw - 1) * ONE, d=ONE)
            elif family == 2:
                transform = dict(a=ONE, b=rng.randrange(-ONE, ONE),
                                 c=rng.randrange(-ONE // 2, ONE // 2), d=ONE)
            src = SRC_BASE + index * 0x80000
            dst = DST_BASE + index * 0x200000
            stride = ((sw * 2 + 31) // 32) * 32
            out_stride = ((2 * (rx + rw) + 31) // 32) * 32
            descriptors.append(Descriptor(src, stride, sw, sh, dst, out_stride,
                                          rx, ry, rw, rh, bg=rng.randrange(65536),
                                          **transform))
            surfaces.append((dst, out_stride, ry + rh + 3))
        latency, stall, bdelay = rng.randrange(0, 41), rng.randrange(0, 71), rng.randrange(20)

    memory = bytearray(MEM_BYTES)
    segments = []

    def segment(address, data, label):
        path = directory / f'{label}.bin'
        path.write_bytes(data)
        memory[address:address + len(data)] = data
        segments.append((address, len(data), path.resolve()))

    for index, (base, stride, height) in enumerate(surfaces):
        segment(base, rng.randbytes(stride * height), f'dst{index}')
    for index, item in enumerate(descriptors):
        if any(item.src == s[0] for s in surfaces):
            continue
        data = bytearray(item.src_stride * max(item.sh, 1))
        for y in range(max(item.sh, 1)):
            for x in range(item.src_stride // 2):
                pattern = number % 4
                if pattern == 0:
                    pixel = rng.randrange(65536)
                elif pattern == 1:
                    pixel = 0xffff if ((x // 4) ^ (y // 4)) & 1 else 0
                elif pattern == 2:
                    pixel = ((x & 31) << 11) | ((y & 63) << 5) | ((x + y) & 31)
                else:
                    pixel = ((x // 8 + 7 * (y // 8)) * 1237 + x + 2 * y) & 0xffff
                struct.pack_into('<H', data, y * item.src_stride + x * 2, pixel)
        segment(item.src, data, f'src{index}')
    words_list = []
    masks = (0xfffff000, 0x0000ffe0, 0x0fff0fff, 0xfffff000,
             0x0000ffe0, 0x0fff0ff0, 0x0fff0ffe, 0x0000ffff)
    for item in descriptors:
        words = item.words()
        if dirty:
            words[:8] = [w | (rng.getrandbits(32) & ~mask)
                         for w, mask in zip(words, masks)]
            words[14:16] = [rng.getrandbits(32), rng.getrandbits(32)]
            if number == 5:
                words[5] |= 15
                words[6] |= 1
        words_list.append(words)
    segment(DESC_BASE, b''.join(struct.pack('<16I', *w) for w in words_list), 'descriptors')
    # Injected failures are compared after recovery. A configuration error stops the table.
    for words in words_list:
        if execute(memory, words):
            break
    expected = []
    for index, (base, stride, height) in enumerate(surfaces):
        path = directory / f'expected{index}.bin'
        path.write_bytes(memory[base:base + stride * height])
        item = Descriptor.decode(words_list[index])
        expected.append((index, base, stride, height, item.rx, item.ry, path.resolve()))
    with (directory / 'config.txt').open('w') as out:
        values = (mode, len(descriptors), error, injection, abort, latency, stall,
                  bandwidth, bdelay, limit, seed, len(segments), len(expected))
        out.write(' '.join(map(str, values)) + '\n')
        for record in segments + expected:
            out.write(' '.join(map(str, record)) + '\n')
    return directory / 'config.txt'
