#!/usr/bin/env python3
# File: scenes.py
# Spec: Task T-RNDB2; rnd-spec v0.3 2.1–2.6.
# Description: Single scene/data description; generate C calls to the actual encoders.
# Clock domain: host.
"""All addresses below are offsets in a DDR arena, relocated only by generated C."""
import argparse
import importlib.util
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('rnd_ref', ROOT / 'verif/block/rnd/rnd_ref.py')
ref = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = ref
spec.loader.exec_module(ref)

WIDTH, HEIGHT = 1280, 720
BASES = (0, 0x200000)
STRIDES = (2560, 5120)
SIZES = (STRIDES[0] * HEIGHT, STRIDES[1] * HEIGHT)
DATA = 0x600000
TEMP = 0x610000
ARENA_BYTES = 0x620000
blob = bytearray()


def resource(data, alignment=32):
    blob.extend(bytes((-len(blob)) % alignment))
    offset = DATA + len(blob)
    blob.extend(data)
    return offset


palette = resource(b''.join(struct.pack('<I', ((64 + i % 192) << 24) |
                                        ((i * 37 % 256) << 16) |
                                        ((i * 71 % 256) << 8) | (i * 19 % 256))
                            for i in range(256)))
sources = {}
for fmt in range(10):
    bpp = ref.BPP[fmt]
    stride = 32 * bpp // 8
    data = bytes((i * 29 + i // stride * 17 + 63) % 256 for i in range(stride * 32))
    sources[fmt] = (resource(data), stride)
rgb_base, rgb_stride = sources[0]
key_offset = rgb_base - DATA + rgb_stride + 2
color_key = int.from_bytes(blob[key_offset:key_offset + 2], 'little')
maps = resource(struct.pack('<64H', *(i % 4 | ((i % 4) << 12) for i in range(64))))
GROUPS = []


def command(op, fmt, rect, **kw):
    common = dict(dst_fmt=fmt, dst_base=BASES[fmt], dst_stride=STRIDES[fmt],
                  clip=(0, 0, WIDTH - 1, HEIGHT - 1), rect=rect,
                  color=0x46d49c, opa=207)
    common.update(kw)
    return getattr(ref, op)(**common)


for fmt in (0, 1):
    y = 96 if fmt == 0 else 384
    for index, op in enumerate(('fill', 'border', 'glyph', 'blit', 'copy',
                                'box_shadow', 'blur', 'tilemap')):
        x = 32 + index * 152
        rect = (x, y, x + 111, y + 95)
        cmds = []
        if op == 'fill':
            cmds += [command(op, fmt, rect, radius=20, flags=1,
                             grad_start=0x9020d0f0, steps=(65000, 140000, -90000, -30000))]
            cmds += [command(op, fmt, (x + 12, y + 24, x + 95, y + 71), radius=9,
                             flags=3, grad_start=0xf0e03090,
                             steps=(-190000, -90000, 160000, 200000))]
        elif op == 'border':
            cmds += [command(op, fmt, rect, radius=23, width=6, sides=15)]
            cmds += [command(op, fmt, (x + 20, y + 24, x + 90, y + 72),
                             radius=12, width=4, sides=5, color=0xf07840)]
        elif op == 'glyph':
            for i, src_fmt in enumerate((2, 3, 4, 5)):
                sx, sy = x + i * 27, y + 20
                base, stride = sources[src_fmt]
                cmds += [command(op, fmt, (sx, sy, sx + 23, sy + 31), src_fmt=src_fmt,
                                 src_base=base, src_stride=stride, src_x=3)]
        elif op == 'blit':
            for i, src_fmt in enumerate((0, 1, 6, 7, 8, 9)):
                sx, sy = x + (i % 3) * 36, y + (i // 3) * 40
                base, stride = sources[src_fmt]
                cmds += [command('fill', fmt, (sx, sy, sx + 31, sy + 31),
                                 color=0x704890, opa=255)]
                cmds += [command(op, fmt, (sx - 2, sy - 2, sx + 31, sy + 31),
                                 clip=(sx, sy, sx + 29, sy + 29), src_fmt=src_fmt,
                                 src_base=base, src_stride=stride,
                                 scale_x=49152, scale_y=49152, flags=((i % 4) << 4) | 15,
                                 palette=palette, key=color_key, rc_color=0x20f080, rc_opa=83)]
        elif op == 'copy':
            cmds += [command('fill', fmt, rect, flags=1, grad_start=0xff1050e0,
                             steps=(0, 110000, 70000, -90000), opa=255)]
            for dx, dy in ((8, 0), (-8, 0), (0, 8), (0, -8)):
                cmds += [command(op, fmt, (x + 16 + dx, y + 16 + dy,
                                          x + 87 + dx, y + 71 + dy), src_fmt=fmt,
                                 src_base=BASES[fmt], src_stride=STRIDES[fmt],
                                 src_x=x + 16, src_y=y + 16)]
        elif op == 'box_shadow':
            cmds += [command(op, fmt, (x + 12, y + 12, x + 99, y + 83),
                             radius=16, blur=7, temp_base=TEMP, color=0xf070c0)]
        elif op == 'blur':
            cmds += [command('fill', fmt, rect, color=0x3040c0, opa=255)]
            for i in range(4):
                cmds += [command('fill', fmt, (x + 12 + i * 23, y + 16,
                                              x + 21 + i * 23, y + 79), color=0xf0c030)]
            cmds += [command(op, fmt, rect, radius=5, temp_base=TEMP)]
        else:
            for i, src_fmt in enumerate((0, 1, 6, 7)):
                sx, sy = x + (i % 2) * 56, y + (i // 2) * 48
                base, _ = sources[src_fmt]
                # Four contiguous tiles fit in each 32x32 resource for both sizes.
                cmds += [command(op, fmt, (sx, sy, sx + 47, sy + 39), src_fmt=src_fmt,
                                 flags=(i & 1) | 4, tile_base=base, map_base=maps,
                                 map_stride=16, map_x=1, map_y=1,
                                 palette=palette, key=color_key)]
        GROUPS.append((f'{op}_{"rgb565" if fmt == 0 else "argb8888"}', fmt, cmds))


# Parameter blocks use RECT-local geometry and the specified eighth-pixel circle grid.
def parameters(words, count):
    return resource(struct.pack('<' + str(count) + 'I',
                                *(v & 0xffffffff for v in
                                  (*words, *((0,) * (count - len(words)))))), 64)


def circle(cx, cy, radius):
    dx, dy = 1 - 8 * cx, 1 - 8 * cy
    q = dx * dx + dy * dy - (8 * radius) ** 2
    return (q & 0xffffffff, (q >> 32) & 65535, 16 * dx + 64, 16 * dy + 64)


def geometry(op, fmt, rect, words, **kw):
    c = command('fill', fmt, rect, **kw)
    return ref.Command(op, **{k: v for k, v in vars(c).items() if k not in ('op', 'args')},
                       args=(parameters(words, 32), 0, 0, 0, 0, 0, 0, 0))


# Append v2 groups: the original sixteen commands/CRCs and their order stay intact.
for fmt in (0, 1):
    y = 240 if fmt == 0 else 544
    for index, op in enumerate(('triangle', 'line', 'arc', 'mask_rect',
                                'affine_blit', 'round_clip', 'cutout')):
        if op == 'mask_rect' and fmt == 0:
            continue  # rnd 2.6: MASK_RECT requires an ARGB target (coordinator confirmed).
        x = 40 + index * 172
        rect = (x, y, x + 127, y + 111)
        cmds = []
        if op == 'triangle':
            # Two halves of one square: the diagonal edge is exactly negated,
            # with complementary inclusion. A second pair disables AA.
            for aa, offset in ((1, 0), (0, 64)):
                r = (x + offset, y + 20, x + offset + 55, y + 75)
                for edges, flags, color in (
                    ((-4, 1, 0, -4, 0, 1, 56, -1, -1), 6, 0x30d0e0),
                    ((52, -1, 0, 52, 0, -1, -56, 1, 1), 8, 0xe06090)):
                    cmds.append(geometry(9, fmt, r, [v * 65536 for v in edges],
                                         flags=flags | aa, color=color))
        elif op == 'line':
            cmds.append(geometry(10, fmt, rect,
                (-20*65536, 39322, 52429, 0, -52429, 39322, 80*65536, 6*65536,
                 *circle(12, 16, 6), *circle(60, 80, 6)), flags=7))
            cmds.append(geometry(10, fmt, rect,
                (-16*65536, 65536, 0, -94*65536, 0, 65536,
                 92*65536, 5*65536, *circle(16, 94, 5), *circle(108, 94, 5)),
                flags=7, color=0xf09030))
        elif op == 'arc':
            # A 270-degree ring (all quadrants except lower right), two round caps.
            cmds.append(geometry(11, fmt, rect,
                (*circle(60, 56, 44), *circle(60, 56, 32),
                 *circle(98, 56, 6), *circle(60, 94, 6),
                 56*65536, 0, -65536, 60*65536, -65536, 0), flags=15))
        elif op == 'mask_rect':
            for k in range(2):
                r = (x + k*64, y, x + k*64 + 59, y + 95)
                cmds.append(command('fill', fmt, r, flags=1, grad_start=0x4010d0f0,
                                    steps=(180000, 150000, -80000, -90000)))
                c = command('fill', fmt, r, flags=k)
                cmds.append(ref.Command(12, **{a: b for a, b in vars(c).items()
                                               if a not in ('op', 'args')},
                    args=(18, ref.xy(r[0]+4, y+8), ref.xy(r[2]-4, y+79), 0, 0, 0, 0, 0)))
        elif op == 'affine_blit':
            for k, src_fmt in enumerate((0, 1, 7)):
                for filtering in (0, 1):
                    sx, sy = x + k*42, y + filtering*56
                    r = (sx, sy, sx+39, sy+47)
                    # Inverse 90-degree rotation with 4/3 scaling and fractional phase.
                    pb = parameters((16384, 31*65536+16384, 0, -49152, 49152, 0), 16)
                    base, stride = sources[src_fmt]
                    c = command('fill', fmt, r, src_fmt=src_fmt, flags=filtering)
                    cmds.append(ref.Command(13, **{a: b for a, b in vars(c).items()
                                                   if a not in ('op', 'args')},
                        args=(base, stride, ref.xy(32, 32), pb, 0, palette, 0, 0)))
        elif op == 'round_clip':
            for k, src_fmt in enumerate((0, 1)):
                sx = x+k*64
                r = (sx, y+16, sx+59, y+95)
                pb = parameters((0, ref.xy(sx+4, y+20), ref.xy(sx+55, y+91)), 16)
                base, stride = sources[src_fmt]
                cmds.append(command('blit', fmt, r, src_fmt=src_fmt, src_base=base,
                                    src_stride=stride, scale_x=32768, scale_y=24576,
                                    flags=128, palette=pb, clip_radius=18))
        else:
            cmds.append(command('box_shadow', fmt, (x+16, y+16, x+111, y+95),
                                radius=20, blur=7, temp_base=TEMP, flags=1,
                                bg=(x+8, y+8, x+103, y+87), bg_radius=18,
                                color=0xf070c0))
        GROUPS.append((f'{op}_{"rgb565" if fmt == 0 else "argb8888"}', fmt, cmds))


def cnum(value):
    return f'0x{value & 0xffffffff:08x}u'


def generate(path):
    lines = ['/* Generated by scenes.py; commands and data have one source. */',
             '#include "rnd.h"', f'#define BOARD_ARENA_BYTES {ARENA_BYTES}u',
             f'#define BOARD_DATA_OFFSET {DATA}u', f'#define BOARD_DATA_BYTES {len(blob)}u',
             f'#define BOARD_GROUP_COUNT {len(GROUPS)}u',
             f'#define BOARD_MAX_COMMANDS {max(len(g[2]) for g in GROUPS)}u',
             'static const uint32_t board_bases[] = {0, 0x200000};',
             'static const uint32_t board_strides[] = {2560, 5120};',
             'static const uint32_t board_sizes[] = {1843200, 3686400};',
             'static const char *const board_names[] = {',
             *(f'    "{g[0]}",' for g in GROUPS), '};',
             'static const unsigned int board_formats[] = {' +
             ', '.join(str(g[1]) for g in GROUPS) + '};',
             'static const uint8_t board_data[] = {']
    for start in range(0, len(blob), 16):
        lines.append('    ' + ','.join(str(v) for v in blob[start:start + 16]) + ',')
    lines += ['};']
    for group, (_, _, cmds) in enumerate(GROUPS):
        lines += [f'static unsigned int board_group_{group}(uint32_t base,',
                  '                                  struct rnd_command *out)', '{']
        for i, c in enumerate(cmds):
            w = c.args
            lines += ['        {', '            struct rnd_common c = {',
                      f'                .dst_base = base + {cnum(c.dst_base)},',
                      f'                .dst_stride = {c.dst_stride}, .dst_fmt = {c.dst_fmt},',
                      f'                .src_fmt = {c.src_fmt}, .flags = {c.flags},',
                      '                .clip = {' + ', '.join(map(str, c.clip)) + '},',
                      '                .rect = {' + ', '.join(map(str, c.rect)) + '},',
                      f'                .color = {cnum(c.color)}, .opa = {c.opa}', '            };']
            target = f'&out[{i}], &c'
            if c.op == 1:
                lines += ['            const int32_t steps[] = {' +
                          ', '.join(str(ref.signed(v, 32)) for v in w[2:6]) + '};',
                          f'            rnd_fill({target}, {w[0]}, {cnum(w[1])}, steps);']
            elif c.op == 2:
                lines += [f'            rnd_border({target}, {w[0]}, {w[1] & 4095}, {w[1] >> 16});']
            elif c.op in (3, 4, 5):
                source = '{base + ' + cnum(w[0]) + f', {w[1]}, {w[2] & 65535}, {w[2] >> 16}' + '}'
                if c.op == 4:
                    pal = 'base + ' + cnum(w[5]) if w[5] else '0'
                    lines += [f'            const struct rnd_blit b = {{{source},',
                              f'                {w[3]}, {w[4]}, {pal}, {w[6] & 65535},',
                              f'                {cnum(w[7] & 0xffffff)}, {w[7] >> 24},',
                              f'                {pal if c.flags & 128 else 0}, '
                              f'{(w[6] >> 16) & 4095}' + '};',
                              f'            rnd_blit({target}, &b);']
                else:
                    lines += [f'            const struct rnd_source s = {source};',
                              f'            rnd_{"glyph" if c.op == 3 else "copy"}({target}, &s);']
            elif c.op == 6 and c.flags & 1:
                bg = ref.rectangle_words(w[3], w[4])
                lines += ['            const struct rnd_rect bg = {' +
                          ', '.join(map(str, bg)) + '};',
                          f'            rnd_box_shadow_cutout({target}, {w[0]}, {w[1]},',
                          f'                base + {cnum(w[2])}, &bg, {w[5]});']
            elif c.op == 6:
                lines += [f'            rnd_box_shadow({target}, {w[0]}, {w[1]},',
                          f'                           base + {cnum(w[2])});']
            elif c.op == 7:
                lines += [f'            rnd_blur({target}, {w[0]}, base + {cnum(w[1])});']
            elif c.op == 8:
                lines += ['            const struct rnd_tilemap t = {',
                          f'                base + {cnum(w[0])}, base + {cnum(w[1])}, {w[2]},',
                          f'                {w[3] & 65535}, {w[3] >> 16}, '
                          f'base + {cnum(w[5])}, {w[6]}' + '};',
                          f'            rnd_tilemap({target}, &t);']
            elif c.op in (9, 10, 11):
                name = {9: 'triangle', 10: 'line', 11: 'arc'}[c.op]
                lines += [f'            rnd_{name}({target}, base + {cnum(w[0])});']
            elif c.op == 12:
                mask = ref.rectangle_words(w[1], w[2])
                lines += ['            const struct rnd_rect mask = {' +
                          ', '.join(map(str, mask)) + '};',
                          f'            rnd_mask_rect({target}, &mask, {w[0]});']
            elif c.op == 13:
                lines += ['            const struct rnd_affine a = {',
                          f'                base + {cnum(w[0])}, {w[1]}, '
                          f'{w[2] & 65535}, {w[2] >> 16},',
                          f'                base + {cnum(w[3])}, base + {cnum(w[5])},',
                          f'                {w[6]}, {w[4]}, {cnum(w[7] & 0xffffff)}, '
                          f'{w[7] >> 24}' + '};',
                          f'            rnd_affine_blit({target}, &a);']
            lines += ['        }']
        lines += [f'    return {len(cmds)};', '}']
    lines += ['static unsigned int board_commands(unsigned int group, uint32_t base,',
              '                                   struct rnd_command *out)', '{',
              '    static unsigned int (*const builders[])(uint32_t, struct rnd_command *) = {']
    lines += [f'        board_group_{group},' for group in range(len(GROUPS))]
    lines += ['    };', '    return builders[group](base, out);', '}']
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--header', type=Path, required=True)
    generate(parser.parse_args().header)
