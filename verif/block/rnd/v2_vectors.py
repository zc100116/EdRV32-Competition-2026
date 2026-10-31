#!/usr/bin/env python3
# File: v2_vectors.py
# Spec: rnd 2.3, 2.6, 5–7; rnd-testplan RN-19, RN-21–29.
# Description: Software geometry/parameter encoders and independent v2 stimuli.
# Clock domain: host.
from dataclasses import replace
from math import cos, isqrt, pi, sin

from rnd_ref import Command, blit, box_shadow, fill, store, xy

PARAM = 0x48000
SRC = 0x20000
PAL = 0x50000
TEMP = 0x60000


def put_parameters(memory, address, words, size=128):
    memory[address:address + size] = bytes(size)
    for k, word in enumerate(words):
        store(memory, address + 4 * k, 4, word & 0xffffffff)


def circle(rect, cx8, cy8, r8):
    """Coordinates and radius in eighths; encode q at RECT origin + (1/8,1/8)."""
    x, y = 8 * rect[0] + 1 - cx8, 8 * rect[1] + 1 - cy8
    q = x * x + y * y - r8 * r8
    return (q & 0xffffffff, (q >> 32) & 65535, 16 * x + 64, 16 * y + 64)


def edge(rect, a, b):
    ax, ay = a
    bx, by = b
    ex, ey = ay - by, bx - ax
    e0 = (rect[0] - ax) * ex + (rect[1] - ay) * ey
    return tuple(v * 65536 for v in (e0, ex, ey))


def triangle(rect, vertices, aa=1, **common):
    a, b, c = vertices
    cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    if cross == 0:
        rect = (1, 1, 0, 0)
    if (b[0] - a[0]) * (c[1] - a[1]) < (b[1] - a[1]) * (c[0] - a[0]):
        vertices = tuple(reversed(vertices))
    words = []
    flags = aa
    for k in range(3):
        a, b = vertices[k], vertices[(k + 1) % 3]
        words.extend(edge(rect, a, b))
        if b[1] < a[1] or b[1] == a[1] and b[0] > a[0]:
            flags |= 2 << k
    return Command(9, rect=rect, flags=flags, **common), words


def line(rect, start8, end8, half8, aa=1, caps=3, **common):
    dx, dy = end8[0] - start8[0], end8[1] - start8[1]
    length8 = isqrt(dx * dx + dy * dy)
    if length8:
        tx, ty = dx * 65536 // length8, dy * 65536 // length8
        ox, oy = 8 * rect[0] - start8[0], 8 * rect[1] - start8[1]
        words = [(ox * tx + oy * ty) // 8, tx, ty,
                 (-ox * ty + oy * tx) // 8, -ty, tx, length8 * 8192, half8 * 8192]
    else:
        words = [-65536, 0, 0, 0, 0, 0, 0, half8 * 8192]
    words += list(circle(rect, *start8, half8)) + list(circle(rect, *end8, half8))
    return Command(10, rect=rect, flags=aa | (caps << 1), **common), words


def arc(rect, variant, aa=1, caps=3, angles=None, **common):
    cx, cy, outer, inner = 96, 80, 64, 32
    if variant == 'wide':
        inner = 0
    start, end = angles or {'cross0': (330, 30), 'half': (0, 180),
                           'large': (0, 270), 'overlap': (0, 5)}.get(variant, (0, 90))
    points = [(cos(deg * pi / 180), sin(deg * pi / 180)) for deg in (start, end)]
    middle, cap_radius = (outer + inner) // 2, (outer - inner) // 2
    words = list(circle(rect, cx, cy, outer)) + list(circle(rect, cx, cy, inner))
    for co, si in points:
        words += list(circle(rect, cx + round(middle * co), cy + round(middle * si),
                             cap_radius))
    flags = aa | (caps << 1)
    if (end - start) % 360 > 180:
        flags |= 8
    if variant == 'full':
        flags |= 16
    if inner == 0:
        flags |= 32
    (cs, ss), (ce, se) = points
    for ex, ey in ((round(-ss * 65536), round(cs * 65536)),
                   (round(se * 65536), round(-ce * 65536))):
        words += [((8 * rect[0] - cx) * ex + (8 * rect[1] - cy) * ey) // 8, ex, ey]
    return Command(11, rect=rect, flags=flags, **common), words


def affine(*, param=PARAM, src_base=SRC + 3, src_fmt=1, src_stride=277,
           source_size=(65, 49), radius=0, key=0x1234, rc_opa=128, **common):
    return Command(13, src_fmt=src_fmt,
                   args=(src_base, src_stride, xy(*source_size), param, radius, PAL,
                         key, 0x80a040 | (rc_opa << 24)), **common)


def matrix(name):
    return {
        'identity': (32768, 32768, 65536, 0, 0, 65536),
        'rotate90': (20 * 65536 + 32768, 32768, 0, 65536, -65536, 0),
        'rotate': (5 * 65536, -65536, 56756, 32768, -32768, 56756),
        'skew+': (32768, 32768, 65536, 16384, 32768, 65536),
        'skew-': (4 * 65536, 4 * 65536, 65536, -16384, -32768, 65536),
        'scale': (32768, 32768, 2 * 65536, 0, 0, 3 * 65536),
        'flip': (25 * 65536, 20 * 65536, -65536, 0, 0, -65536),
        'negative': (-1, -32769, 32768, 0, 0, 32768),
        'signed48': (32768, 32768, 0x7fffffff, 0, -0x7fffffff, 0),
        'fourblocks': (8 * 65536, 8 * 65536, 65536, 0, 0, 65536),
        'conflict': (32768, 32768, 8 * 65536, 0, 0, 8 * 65536),
        'outside': (-100 * 65536, -100 * 65536, 0, 0, 0, 0),
    }[name]


def selections(tier):
    if tier == 'perf':
        return [(29, ('g1',), 1)] + [(29, (name, fmt, bilinear), 1)
            for name in ('identity', 'rotate', 'skew+', 'scale')
            for fmt in (0, 1, 7) for bilinear in (0, 1)]
    if tier == 'smoke':
        return [(21, ('shared', 1), 1), (21, ('shared', 0), 1),
                (22, ('diagonal', 1, 3), 1), (22, ('zero', 1, 3), 1),
                (23, ('cross0', 1, 3), 1), (23, ('large', 1, 3), 1),
                (23, ('full', 1, 3), 1), (24, (1, 0, 128), 1),
                (25, ('blit', 1, 7, 1), 1), (25, ('shadow', 1, 0, 5), 1),
                (26, ('rotate90', 0, 1, 1, 0), 1),
                (26, ('skew-', 1, 1, 1, 0), 1),
                (27, (127, 255, 1), 1), (27, (0, 0, 0), 1),
                (28, ('boundary',), 1), (28, ('rewrite',), 1)]
    return ([(21, (name, aa), 1) for name in
             ('shared', 'reverse', 'tiny', 'empty', 'gradientH', 'gradientV', 'split', 'tail')
             for aa in (0, 1)]
            + [(22, (name, aa, caps), 1) for name in ('horizontal', 'vertical', 'diagonal',
                 'zero', 'half') for aa in (0, 1) for caps in range(4)]
            + [(23, (name, aa, caps), 1) for name in
                 ('cross0', 'half', 'small', 'large', 'full', 'wide', 'empty', 'overlap')
                 for aa in (0, 1) for caps in range(4)]
            + [(24, (radius, keep, alpha), 1) for radius in (0, 1, 4095)
                 for keep in (0, 1) for alpha in (0, 1, 128, 255)]
            + [(25, (kind, enabled, fmt, radius), 1) for kind in ('blit', 'shadow')
                 for enabled in (0, 1) for fmt in ((0, 1, 7) if kind == 'blit' else (0, 1))
                 for radius in (0, 1, 4095)]
            + [(26, (name, bilinear, sf, df, mode), 1) for name in
                 ('identity', 'rotate90', 'rotate', 'skew+', 'skew-', 'scale', 'flip',
                  'negative', 'signed48') for bilinear in (0, 1)
                 for sf in (0, 1, 6, 7, 8, 9) for df in (0, 1) for mode in range(4)]
            + [(27, (f, g, sf), 1) for f in (0, 1, 127, 255) for g in (0, 1, 127, 255)
                 for sf in (0, 1, 6, 7, 8, 9)]
            + [(28, (kind,), 1) for kind in ('boundary', 'rewrite', 'conflict', 'outside',
                                            'param_error', 'source_error', 'param_abort',
                                            'source_abort')])


def build(number, variant, rng, memory, metadata, common=None, param=PARAM):
    randomized = common is not None
    common = dict(common or {})
    common.setdefault('opa', 197)
    rect = common.pop('rect', (-2, -1, 29, 21))
    commands = []
    blocks = []
    if number == 21:
        name, aa = variant
        rect = (1, 1, 0, 0) if name == 'empty' else rect
        vertices = tuple((rng.randrange(-4, 30), rng.randrange(-3, 24)) for _ in range(3)
                         ) if randomized else ((1, 1), (22, 1), (22, 17))
        if name == 'reverse':
            vertices = tuple(reversed(vertices))
        c, p = triangle(rect, vertices, aa, **common)
        if name == 'tiny':
            # Exact coefficients include nonzero samples below the Q16 LSB.
            p = [0, 1, -1, 65536, 0, 0, 65536, 0, 0]
        if name.startswith('gradient') or name == 'split':
            c = replace(c, flags=c.flags | 64 | (128 if name == 'gradientV' else 0))
            p += [0x108040f0, 0x110001, -0x100001, 0x1000001, -0x80001]
        c = replace(c, args=(param,) + (0,) * 7)
        commands = [c]
        blocks = [(param, p)]
        if name == 'shared':
            other, op = triangle(rect, ((1, 1), (22, 17), (1, 17)), aa, **common)
            commands += [replace(other, args=(param + 128,) + (0,) * 7)]
            blocks += [(param + 128, op)]
        if name == 'split':
            commands = [replace(c, clip=(0, 0, 9, 23)), replace(c, clip=(10, 0, 19, 23)),
                        replace(c, clip=(20, 0, 31, 23))]
        if name == 'tail':
            commands = [replace(c, clip=(0, 0, 20, 23))]
    elif number == 22:
        name, aa, caps = variant
        endpoints = {'horizontal': ((24, 56), (176, 56)),
                     'vertical': ((72, 8), (72, 144)),
                     'diagonal': ((-8, 8), (176, 136)),
                     'zero': ((64, 64), (64, 64)), 'half': ((24, 24), (168, 120))}
        if randomized:
            endpoints[name] = tuple((rng.randrange(-32, 240), rng.randrange(-24, 184))
                                    for _ in range(2))
        c, p = line(rect, *endpoints[name], 12 if name == 'half' else 24, aa, caps, **common)
        commands = [replace(c, args=(param,) + (0,) * 7)]
        blocks = [(param, p)]
    elif number == 23:
        name, aa, caps = variant
        if name == 'empty':
            rect = (1, 1, 0, 0)
        angles = (rng.randrange(360), rng.randrange(360)) if randomized else None
        if angles and angles[0] == angles[1]:
            rect = (1, 1, 0, 0)
        c, p = arc(rect, name, aa, caps, angles, **common)
        commands = [replace(c, args=(param,) + (0,) * 7)]
        blocks = [(param, p)]
    elif number == 24:
        radius, keep, alpha = variant
        common.pop('dst_fmt', None)
        commands = [Command(12, dst_fmt=1, rect=rect, flags=keep,
                            args=(radius, xy(-1, 2), xy(19, 18), 0, 0, 0, 0, 0), **common)]
        c = commands[0]
        for y in range(24):
            for x in range(32):
                memory[c.dst_base + y * c.dst_stride + 4 * x + 3] = alpha
    elif number == 25:
        kind, enabled, fmt, radius = variant
        if kind == 'blit':
            commands = [blit(src_fmt=fmt, src_base=SRC + 1, src_stride=137,
                             palette=param if enabled else PAL, clip_radius=radius,
                             rect=rect, flags=128 if enabled else 0, **common)]
            blocks = [(param, [PAL, xy(3, -2), xy(23, 19)])]
        else:
            commands = [box_shadow(dst_fmt=fmt, radius=7, blur=8, temp_base=TEMP,
                                  rect=rect, bg=(1, 3, 24, 18), bg_radius=radius,
                                  flags=enabled, **common)]
    else:
        sf, df, flags = 1, 1, 1
        name = 'identity'
        if number == 26:
            name, bilinear, sf, df, mode = variant
            if name == 'signed48':
                rect = (-32768, -32768, 29, 21)
            flags = bilinear | (4 if mode & 1 else 0) | (8 if mode & 2 else 0)
            flags |= (mode << 4) | (128 if mode & 1 else 0)
        elif number == 27:
            f, g, sf = variant
            name = 'fourblocks'
        elif number == 28:
            name = variant[0] if variant[0] in ('conflict', 'outside') else 'identity'
            rect = (-1, -1, 65, 33)
            common.update(clip=(0, 0, 65, 33), dst_stride=280)
        elif number == 29:
            if variant[0] == 'g1':
                rect = (0, 0, 255, 63)
                c, p = triangle(rect, ((-1000, -1000), (4000, -1000), (-1000, 4000)),
                                1, dst_stride=1024, clip=rect, opa=128)
                commands = [replace(c, args=(param,) + (0,) * 7)]
                blocks = [(param, p)]
            else:
                name, sf, flags = variant
                rect = (0, 0, 255, 127)
                common.update(dst_base=0x100000, dst_stride=1024, clip=rect)
            metadata.update(latency=0, stalls=0, bdelay=0, perf=5 if commands else 6)
        if number == 29 and not commands and name == 'identity' and flags == 1:
            metadata['perf'] = 7
        if not commands:
            common.pop('dst_fmt', None)
            c = affine(param=param, src_fmt=sf, dst_fmt=df, flags=flags, rect=rect,
                       radius=7, source_size=(257, 129) if number == 29 else (65, 49),
                       src_stride=1053 if number == 29 else 277, **common)
            p = list(matrix(name))
            if randomized:
                p = [rng.randrange(-4 * 65536, 12 * 65536) for _ in range(2)]
                p += [rng.randrange(-2 * 65536, 2 * 65536) for _ in range(4)]
            if number == 27:
                p[0:2] = [8 * 65536 + 32768 + f * 256, 8 * 65536 + 32768 + g * 256]
            p += [xy(1, 2), xy(28, 20)]
            commands = [c]
            blocks = [(param, p)]
            if number == 28:
                kind = variant[0]
                if kind == 'outside':
                    metadata['zero_writes'] = 2
                if kind == 'conflict':
                    c = replace(c, args=(*c.args[:2], xy(273, 273), *c.args[3:]))
                    commands = [c]
                if kind == 'rewrite':
                    commands = [c, fill(dst_base=SRC + 4, dst_stride=276,
                                rect=(0, 0, 64, 48), clip=(0, 0, 64, 48), opa=255), c]
                    commands[0] = replace(c, args=(SRC + 4, 276, *c.args[2:]))
                    commands[2] = commands[0]
                if kind.endswith('error') or kind.endswith('abort'):
                    commands += [fill(dst_base=0x14000, opa=255)]
                    metadata.update(latency=40, stalls=0, bdelay=40)
                    if kind.endswith('error'):
                        metadata.update(error=1, injection=6 if kind == 'param_error' else 2)
                    else:
                        metadata['abort'] = 4 if kind == 'param_abort' else 5
    if number in (21, 23) and variant[0] == 'empty':
        metadata['zero_writes'] = 1
    for address, words in blocks:
        put_parameters(memory, address, words)
    return commands
