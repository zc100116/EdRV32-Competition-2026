#!/usr/bin/env python3
# File: vectors.py
# Spec: rnd-testplan RN-01–16, RN-18–19; rnd 2–7.
# Description: Directed boundary cases and ten deterministic random command-list seeds.
# Clock domain: host.
from dataclasses import replace
from pathlib import Path
import random

from rnd_ref import (BPP, Command, area, blit, blur, border, box_shadow, copy, execute,
                     fill, glyph, load, store, temp_region, tilemap)

DESC = 0x1000
DST = 0x10000
SRC = 0x20000
PAL = 0x50000
TEMP = 0x60000
MAP = 0x70000
TILE = 0x80000


def selections(tier):
    if tier == 'perf':
        return [(18, (name, latency), 1) for latency in (0, 40)
                for name in ('argb', 'rgb565', 'blit', 'glyph')]
    if tier == 'full':
        return ([(5, (fmt, sides, width), 1) for fmt in (0, 1)
                 for sides in range(16) if sides not in (0, 1, 2, 4, 8, 15)
                 for width in (1, 7, 9, 20)]
                + [(11, (fmt, radius, corner), 1) for fmt in (0, 1)
                   for radius in (1, 31) for corner in (0, 4095)]
                + [(12, (fmt, radius), 1) for fmt in (0, 1) for radius in (0, 31)]
                + [(15, ('abort', phase), 1) for phase in (1, 2, 3)]
                + [(19, 'random', seed) for seed in range(1, 11)])
    cases = [(1, (fmt, opa, alpha), 1) for fmt in (0, 1)
             for opa in (0, 1, 128, 254, 255) for alpha in (0, 1, 128, 255)]
    cases += [(2, (fmt, name), 1) for fmt in (0, 1)
              for name in ('partial', 'outside', 'negative', 'emptyx', 'emptyy', 'one')]
    cases += [(2, (fmt, offset), 1) for fmt in (0, 1)
              for offset in range(0, 32, 2 << fmt)]
    cases += [(3, (fmt, radius, width, height), 1) for fmt in (0, 1)
              for radius in (0, 1, 2, 7, 4095) for width, height in ((19, 16), (1, 2), (2, 1))]
    cases += [(4, (fmt, vertical, negative, split), 1) for fmt in (0, 1)
              for vertical in (0, 1) for negative in (0, 1) for split in (0, 1)]
    cases += [(5, (fmt, sides, width), 1) for fmt in (0, 1)
              for sides in (0, 1, 2, 4, 8, 15) for width in (1, 7, 9, 20)]
    cases += [(6, (fmt, srcfmt, offset), 1) for fmt in (0, 1)
              for srcfmt in (2, 3, 4, 5) for offset in range(8 // BPP[srcfmt])]
    cases += [(7, (fmt, srcfmt, offset), 1) for fmt in (0, 1)
              for srcfmt in (0, 1, 6, 7, 8, 9) for offset in (0, 1, 7, 31)]
    cases += [(8, (fmt, scale, flips), 1) for fmt in (0, 1)
              for scale in (0, 65536 // 2, 65536 * 2 // 7, 98304, 4 * 65536, 16 * 65536)
              for flips in (0, 1, 2, 3)]
    cases += [(9, (fmt, srcfmt, mode, recolor, alpha), 1) for fmt in (0, 1)
              for srcfmt in (0, 1, 7) for mode in range(4) for recolor in (0, 128, 255)
              for alpha in (0, 255)]
    cases += [(10, (fmt, direction), 1) for fmt in (0, 1)
              for direction in ('different', 'same', 'ul', 'ur', 'dl', 'dr')]
    cases += [(11, (fmt, radius, corner), 1) for fmt in (0, 1)
              for radius in (0, 8) for corner in (0, 4095)]
    cases += [(12, (fmt, radius), 1) for fmt in (0, 1) for radius in (1, 8)]
    cases += [(13, (fmt, srcfmt, tile16), 1) for fmt in (0, 1)
              for srcfmt in (0, 1, 6, 7) for tile16 in (0, 1)]
    cases += [(14, 'chain', 1), (16, 'registers', 1)]
    cases += [(15, ('bus', kind), 1) for kind in range(1, 6)]
    cases += [(15, ('op', op), 1) for op in (0, 9, 255)]
    cases += [(15, ('format', (op, fmt)), 1) for op, allowed in
              ((3, (2, 3, 4, 5)), (4, (0, 1, 6, 7, 8, 9)), (8, (0, 1, 6, 7)))
              for fmt in range(16) if fmt not in allowed]
    cases += [(15, ('copy', fmt), 1) for fmt in (0, 2, 15)]
    cases += [(15, ('mode', mode), 1) for mode in range(4, 8)]
    return cases


def pattern_memory(size, rng):
    # Repeated random blocks make unowned bytes nonzero without expensive per-byte RNG calls.
    pattern = rng.randbytes(4096)
    return bytearray((pattern * ((size + 4095) // 4096))[:size])


def configure(number, variant, seed):
    rng = random.Random(0x524e4400 + number * 100 + seed)
    c = fill()
    commands = [c]
    metadata = dict(number=number, error=0, injection=0, abort=0, latency=3,
                    stalls=30, bdelay=3, seed=seed, perf=0, zero_writes=0)
    alpha = None
    special_source = False
    split_reference = None
    mem_size = 0x80000
    if number == 1:
        fmt, opa, alpha = variant
        commands = [fill(dst_fmt=fmt, dst_stride=66 if fmt == 0 else 132, opa=opa)]
    elif number == 2:
        fmt, name = variant
        changes = dict(dst_fmt=fmt, dst_stride=70 if fmt == 0 else 140)
        if isinstance(name, int):
            changes.update(dst_base=DST + name, rect=(0, 0, 30, 7))
        else:
            changes['rect'] = {'partial': (25, 19, 40, 31), 'outside': (40, 30, 50, 40),
                               'negative': (-9, -5, 7, 8), 'emptyx': (8, 2, 7, 9),
                               'emptyy': (2, 8, 9, 7), 'one': (31, 23, 31, 23)}[name]
            metadata['zero_writes'] = int(name in ('outside', 'emptyx', 'emptyy'))
        commands = [fill(**changes)]
    elif number == 3:
        fmt, radius, width, height = variant
        commands = [fill(dst_fmt=fmt, radius=radius, rect=(4, 3, 3 + width, 2 + height))]
    elif number == 4:
        fmt, vertical, negative, split = variant
        c = fill(dst_fmt=fmt, flags=1 | (vertical << 1), radius=7,
                 rect=(-2, -3, 31, 23), grad_start=0xe1d0a040 if negative else 0x10203040,
                 steps=tuple(sign * value for value in (0x110123, 0x1000001, 0x0f8000, 0x080001)
                             for sign in (-1 if negative else 1,)))
        commands = [c]
        if split:
            commands = [replace(c, clip=(0, 0, 9, 23)), replace(c, clip=(10, 0, 20, 23)),
                        replace(c, clip=(21, 0, 31, 23))] if not vertical else [
                        replace(c, clip=(0, 0, 31, 6)), replace(c, clip=(0, 7, 31, 15)),
                        replace(c, clip=(0, 16, 31, 23))]
            split_reference = c
    elif number == 5:
        fmt, sides, width = variant
        commands = [border(dst_fmt=fmt, radius=7, width=width, sides=sides)]
    elif number == 6:
        fmt, srcfmt, offset = variant
        commands = [glyph(dst_fmt=fmt, src_fmt=srcfmt, src_base=SRC + 1,
                          src_stride=37, src_x=offset, src_y=1)]
    elif number == 7:
        fmt, srcfmt, offset = variant
        commands = [blit(dst_fmt=fmt, src_fmt=srcfmt, src_base=SRC + offset,
                         src_stride=137, src_x=1, src_y=1, palette=PAL)]
    elif number == 8:
        fmt, scale, flips = variant
        commands = [blit(dst_fmt=fmt, src_fmt=1, src_base=SRC + 3, src_stride=1301,
                         src_x=1, src_y=1, scale_x=scale, scale_y=scale, flags=flips,
                         rect=(-2, -1, 15, 12), clip=(3, 2, 14, 11))]
        mem_size = 0xa0000
    elif number == 9:
        fmt, srcfmt, mode, recolor, alpha = variant
        commands = [blit(dst_fmt=fmt, src_fmt=srcfmt, src_base=SRC + 1, src_stride=137,
                         palette=PAL, flags=4 | 8 | (mode << 4), key=0x1234,
                         rc_color=0xf02080, rc_opa=recolor)]
        special_source = True
    elif number == 10:
        fmt, direction = variant
        size = 2 << fmt
        offsets = {'ul': (-2, -1), 'ur': (2, -1), 'dl': (-2, 1),
                   'dr': (2, 1), 'same': (0, 0), 'different': (1, 1)}
        dx, dy = offsets[direction]
        commands = [copy(dst_fmt=fmt, src_fmt=fmt, src_base=SRC + 3
                         if direction == 'different' else DST,
                         src_stride=137 if direction == 'different' else 132,
                         src_x=5, src_y=4, rect=(5 + dx, 4 + dy, 23 + dx, 17 + dy))]
    elif number == 11:
        fmt, radius, corner = variant
        commands = [box_shadow(dst_fmt=fmt, radius=corner, blur=radius, temp_base=TEMP,
                               rect=(-3, 1, 18, 16), clip=(0, 3, 28, 20))]
    elif number == 12:
        fmt, radius = variant
        commands = [blur(dst_fmt=fmt, radius=radius, temp_base=TEMP,
                         rect=(1, 2, 5, 4), clip=(2, 2, 4, 3))]
    elif number == 13:
        fmt, srcfmt, tile16 = variant
        commands = [tilemap(dst_fmt=fmt, src_fmt=srcfmt, flags=tile16 | 4,
                            tile_base=TILE, map_base=MAP, map_stride=16, map_x=7, map_y=13,
                            palette=PAL, key=0x1234, rect=(-1, -2, 30, 21))]
        mem_size = TILE + 4096 * (16 if tile16 else 8) ** 2 * BPP[srcfmt] // 8 + 4096
    elif number == 14:
        commands = [fill(opa=255), border(width=2, radius=3),
                    glyph(src_fmt=3, src_base=SRC + 1, src_stride=37),
                    blit(src_fmt=1, src_base=SRC + 3, src_stride=137),
                    copy(src_fmt=1, src_base=DST, src_stride=132, src_x=2, src_y=2,
                         dst_base=DST + 0x2000),
                    blit(src_fmt=1, src_base=DST + 0x2000, src_stride=132, src_x=2, src_y=2),
                    blur(radius=1, temp_base=TEMP),
                    box_shadow(radius=7, blur=1, temp_base=TEMP)]
        commands += [fill(opa=opacity, color=rng.randrange(1 << 24))
                     for opacity in (1, 64, 128, 254)]
    elif number == 15:
        kind, value = variant
        first = blit(src_fmt=1, src_base=SRC + 3, src_stride=137, opa=255)
        metadata['latency'] = 40
        metadata['bdelay'] = 40
        metadata['stalls'] = 0
        if kind == 'bus':
            metadata['injection'] = value
            metadata['error'] = 2 if value == 5 else 1
            if value == 4:
                first = replace(first, src_fmt=7, args=(*first.args[:5], PAL, 0, 0))
        elif kind == 'abort':
            metadata['abort'] = value
        else:
            metadata['error'] = 3
            if kind == 'op':
                first = replace(first, op=value)
            elif kind == 'format':
                op, fmt = value
                first = replace(first, op=op, src_fmt=fmt)
            elif kind == 'copy':
                first = replace(first, op=5, src_fmt=value)
            elif kind == 'mode':
                first = replace(first, flags=value << 4)
        commands = [first, fill(dst_base=DST + 0x4000, opa=255, color=0x34fac1)]
    elif number == 16:
        commands = [fill(opa=255, rect=(0, 0, 31, 23))]
        metadata.update(latency=40, stalls=0, bdelay=40)
    elif number == 18:
        variant, read_latency = variant
        metadata.update(latency=read_latency, stalls=0, bdelay=0, perf=1)
        mem_size = 12 * 1024 * 1024
        target = 0x400000
        if variant in ('argb', 'rgb565'):
            fmt = int(variant == 'argb')
            commands = [fill(dst_fmt=fmt, dst_base=target, dst_stride=1280 * (2 << fmt),
                             rect=(0, 0, 1279, 719), clip=(0, 0, 1279, 719), opa=255)]
            metadata['perf'] = 1 if fmt else 2
        elif variant == 'blit':
            commands = [blit(dst_base=target, dst_stride=5120, src_fmt=1, src_base=0x800000,
                             src_stride=4096, rect=(0, 0, 1023, 511),
                             clip=(0, 0, 1279, 719), opa=255)]
            metadata['perf'] = 3
        else:
            commands = [glyph(dst_base=target, dst_stride=5120, src_fmt=3, src_base=SRC + 1,
                              src_stride=9, rect=(i % 64 * 16, i // 64 * 20,
                                                  i % 64 * 16 + 15, i // 64 * 20 + 19),
                              clip=(0, 0, 1279, 719)) for i in range(1000)]
            metadata['perf'] = 4
        if read_latency == 40:
            metadata['perf'] = -metadata['perf']
    elif number == 19:
        mem_size = TILE + 4096 * 256 * 4 + 4096
        commands = []
        for i in range(50):
            op = i % 8 + 1 if i < 8 else rng.randrange(1, 9)
            fmt = rng.randrange(2)
            rect = (rng.randrange(-5, 8), rng.randrange(-4, 5),
                    rng.randrange(9, 32), rng.randrange(6, 24))
            common = dict(dst_fmt=fmt, dst_stride=132, rect=rect,
                          clip=(rng.randrange(4), rng.randrange(3),
                                rng.randrange(20, 32), rng.randrange(16, 24)),
                          color=rng.randrange(1 << 24), opa=rng.randrange(256))
            if op == 1:
                cmd = fill(radius=rng.choice((0, 1, 7, 4095)), flags=rng.randrange(4),
                           grad_start=rng.randrange(1 << 32),
                           steps=tuple(rng.randrange(-0x400000, 0x400000) for _ in range(4)),
                           **common)
            elif op == 2:
                cmd = border(radius=rng.randrange(16), width=rng.randrange(1, 20),
                             sides=rng.randrange(16), **common)
            elif op == 3:
                cmd = glyph(src_fmt=rng.randrange(2, 6), src_base=SRC + rng.randrange(32),
                            src_stride=137, src_x=rng.randrange(8), src_y=1, **common)
            elif op == 4:
                cmd = blit(src_fmt=rng.choice((0, 1, 6, 7, 8, 9)),
                           src_base=SRC + rng.randrange(32), src_stride=137,
                           src_x=rng.randrange(8), src_y=1,
                           scale_x=rng.choice((0, 32768, 65536)),
                           scale_y=rng.choice((0, 32768, 65536)),
                           flags=rng.randrange(16) | (rng.randrange(4) << 4), palette=PAL,
                           key=rng.randrange(65536), rc_color=rng.randrange(1 << 24),
                           rc_opa=rng.randrange(256), **common)
            elif op == 5:
                cmd = copy(src_fmt=fmt, src_base=SRC + rng.randrange(32), src_stride=137,
                           src_x=rng.randrange(8), src_y=1, **common)
            elif op == 6:
                cmd = box_shadow(radius=rng.randrange(20), blur=rng.choice((0, 1, 8, 31)),
                                 temp_base=TEMP, **common)
            elif op == 7:
                cmd = blur(radius=rng.choice((0, 1, 8, 31)), temp_base=TEMP, **common)
            else:
                cmd = tilemap(src_fmt=rng.choice((0, 1, 6, 7)), flags=rng.randrange(2) | 4,
                              tile_base=TILE, map_base=MAP, map_stride=16,
                              map_x=rng.randrange(16), map_y=rng.randrange(16),
                              palette=PAL, key=0x1234, **common)
            commands.append(cmd)
        metadata.update(latency=rng.randrange(0, 41), stalls=rng.randrange(15, 60),
                        bdelay=rng.randrange(1, 41))
    memory = pattern_memory(mem_size, rng)
    # RN-01/09: destination alpha planes explicitly hit all straight-alpha branches.
    if alpha is not None and commands[0].dst_fmt == 1:
        for y in range(24):
            for x in range(32):
                memory[DST + y * commands[0].dst_stride + x * 4 + 3] = alpha
    # Map entries cycle all flips and both extreme tile numbers across multiple rows.
    for y in range(8):
        for x in range(8):
            store(memory, MAP + y * 16 + 2 * x, 2,
                  (4095 if (x + y) & 1 else 0) | (((x + 2 * y) % 4) << 12) | 0xc000)
    if number == 13 and commands[0].src_fmt == 0:
        tile_size = 16 if commands[0].flags & 1 else 8
        for tile in (0, 4095):
            for i in range(tile_size * tile_size):
                if i % 3 == 0:
                    store(memory, TILE + tile * tile_size * tile_size * 2 + i * 2, 2, 0x1234)
    if number == 12 and commands[0].dst_fmt == 0:
        # RN-12 / rnd v0.2: this red checker exposes premature horizontal P565 truncation.
        for y in range(2, 4):
            for x in range(2, 5):
                store(memory, DST + y * commands[0].dst_stride + x * 2, 2,
                      0x1000 if (x + y) & 1 else 0)
    if number in (7, 8):
        source = commands[0]
        fmt = source.src_fmt
        if fmt in (0, 1):
            base, stride = source.args[:2]
            extent = 290 if number == 8 else 32
            # RN-07 checkerboard and RN-08 numbered grid reveal sample origins and flips.
            for y in range(extent):
                for x in range(extent):
                    if fmt == 0:
                        pixel = 0xf800 if ((x // 3) ^ (y // 3)) & 1 else 0x07ff
                    else:
                        pixel = (255 << 24) | ((x % 256) << 16) | ((y % 256) << 8)
                        pixel |= (x + y * 17) % 256
                    store(memory, base + y * stride + x * (2 << fmt), 2 << fmt, pixel)
    if special_source:
        fmt = commands[0].src_fmt
        for y in range(24):
            for x in range(32):
                address = SRC + 1 + y * 137 + x * max(BPP[fmt] // 8, 1)
                if fmt == 0:
                    store(memory, address, 2, 0x1234 if (x + y) & 1 else 0xcdef)
                elif fmt == 1:
                    store(memory, address, 4, ((0, 1, 128, 255)[(x + y) % 4] << 24)
                          | (0x1234 if (x + y) & 1 else 0x8312fe))
    # Palette alpha planes combine transparent, nearly transparent, middle and opaque entries.
    for i in range(256):
        store(memory, PAL + 4 * i, 4, ((0, 1, 128, 255)[i % 4] << 24)
              | ((i * 73 % 256) << 16) | ((i * 37 % 256) << 8) | (i * 19 % 256))
    for index, command in enumerate(commands):
        memory[DESC + index * 64:DESC + (index + 1) * 64] = command.encode()
    # Read errors do not specify how much of the current command writes before stopping.
    # partial is used ONLY for bytes actually written; every other byte must equal initial.
    partial = bytearray(memory)
    if (metadata['error'] or metadata['abort']) and not commands[0].illegal():
        execute(partial, commands[:1])
    recovery = bytearray(memory)
    repaired = list(commands)
    if metadata['error'] == 3:
        repaired[0] = fill(opa=255)
        recovery[DESC:DESC + 64] = repaired[0].encode()
    expected = bytearray(recovery)
    result = execute(expected, repaired)
    if split_reference is not None:
        whole = bytearray(memory)
        execute(whole, [split_reference])
        assert whole == expected, ('RN-04 split mismatch', variant)
    temps = [temp_region(c) for c in commands if not c.illegal() and c.op in (6, 7)]
    metadata.update(count=len(commands), memory_size=len(memory), pixels=result.pixels,
                    expected_done=result.completed)
    return metadata, commands, memory, expected, partial, recovery, temps


def generate(directory, number, variant, seed):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    meta, commands, memory, expected, partial, recovery, temps = configure(number, variant, seed)
    paths = []
    for name, data in (('initial', memory), ('expected', expected),
                       ('partial', partial), ('recovery', recovery)):
        path = directory / f'{name}.bin'
        path.write_bytes(data)
        paths.append(str(path.resolve()))
    keys = ('number', 'count', 'error', 'injection', 'abort', 'latency', 'stalls',
            'bdelay', 'seed', 'perf', 'zero_writes', 'memory_size', 'pixels', 'expected_done')
    config = directory / 'config.txt'
    lines = [' '.join(str(meta[k]) for k in keys), *paths, str(len(temps))]
    lines += [f'{base} {size}' for base, size in temps]
    config.write_text('\n'.join(lines) + '\n')
    return config.resolve()
