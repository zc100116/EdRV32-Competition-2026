#!/usr/bin/env python3
"""Generate bit-exact sampling vectors using tools.gpu.model.texture.Texture."""
from pathlib import Path
import random
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.gpu.model.texture import Texture
from tools.gpu.model.arithmetic import d, logarithm
from tools.gpu.scene import pack

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
rng = random.Random(0x4a2026)
ram = rng.randbytes(192 * 1024)
palettes = [[rng.randrange(1 << 20) for _ in range(256)] for _ in range(16)]
(out / 'ram.hex').write_text(''.join(f'{int.from_bytes(ram[k:k+32], "little"):064x}\n'
                                   for k in range(0, len(ram), 32)))
(out / 'palette.hex').write_text(''.join(f'{v:05x}\n' for group in palettes for v in group))
# Each case has one frozen descriptor followed by 64 input groups. The last three
# runs measure steady throughput; nearest conflict groups exercise PERF5 separately.
cases = []
for fmt in range(3):
    for logw in range(3, 9):
        for logh in range(3, 9):
            for mode in range(3):
                cases.append((fmt, logw, logh, mode, (logw * 7 - logh * 11) % 256 - 128,
                              False, False, 16))
# Every single mip level, including rectangular padded tails, each filter and format.
for fmt in range(3):
    for mode in range(3):
        for bias in [-128, -1, 0, 1, 127]:
            cases.append((fmt, 8, 3, mode, bias, False, False, 64))
# Quads override filtering, bias and group; alpha zero must retain texture coverage.
for fmt in range(3):
    cases.append((fmt, 6, 6, 2, 127, True, False, 64))
# Explicit nearest conflicts and same-word merging (I4/I8), plus full-rate streams.
for fmt in range(3):
    cases.append((fmt, 8, 8, 0, 0, False, True, 128))
for fmt in range(3):
    for mode in range(3):
        cases.append((fmt, 8, 8, mode, 0, False, False, 512))
headers = []
samples = []
expected = []
for case_id, (fmt, logw, logh, mode, bias, quad, conflict, groups) in enumerate(cases):
    levels = max(logw, logh) + 1
    group = case_id % 16
    # Alternate high offsets for smaller textures, exercising all banks and segments.
    desc = dict(OFFSET=0, LOG2_W=logw, LOG2_H=logh, FORMAT=fmt,
                LEVELS=levels, PAL_GROUP=group, SAMPLE=mode, LOD_BIAS=bias)
    texture = Texture(ram, palettes, desc)
    desc['OFFSET'] = ((len(ram) - texture.end) // 32) * 32 if case_id & 1 else 0
    texture = Texture(ram, palettes, desc)
    command = int.from_bytes(pack('CMD_SET_TEX', **desc), 'little')
    headers.append(f'{(groups << 256) | command:068x}\n')
    for j in range(groups):
        mask = rng.randrange(16) if j < groups - 16 else 15
        sample_group = (group + j) % 16
        alpha = (j * 17) % 256
        uv = []
        spans = []
        colors = []
        depths = []
        rgba = []
        for lane in range(4):
            level = (j + lane) % levels
            # Integers and fractional coordinates, signed wrap, zero spans,
            # table endpoint/carry and all mip levels. Pixel-center 1:1 cases
            # compare bilinear with nearest directly in the reference as well.
            u = rng.randrange(-131072, 131072)
            v = rng.randrange(-131072, 131072)
            span = (1 << (16 + level)) + rng.randrange(1 << (15 + level))
            if j % 11 == 0:
                span = 0
            if j % 13 == 0:
                span = 1 << rng.randrange(96)
            if case_id >= len(cases) - 9:
                span = 1 << 16
                if mode == 0:
                    u, v = (j * 4 + lane) * 256 + 128, 128
            if conflict:
                # Four different RGB words / I8 / I4 blocks in bank 0.
                bw, bh = ((2, 2), (2, 1), (1, 1))[fmt]
                word = (lane, 0, lane // 2, lane % 3)[j % 4]
                u, v, span = word * 2 * bw * 256, 0 * bh, 1 << 16
            if j % 17 == 0 and not conflict:
                u, v = ((j + lane) * 256 + 128), ((j - lane) * 256 + 128)
            color = [rng.randrange(256) for _ in range(3)]
            if quad:
                color = [255] * 3
            depth = rng.randrange(65536)
            lod = logarithm(span) if span else 0
            texel = texture.sample(u, v, lod, sample_group if quad else None, nearest=quad)
            if not quad and mode == 1 and span == (1 << 16) and bias == 0:
                if (u & 255) == 128 and (v & 255) == 128:
                    assert texel == texture.texel(u >> 8, v >> 8, 0, group)
            result = [d(a * b) for a, b in zip(texel[:3], color)]
            result.append(d(texel[3] * alpha) if quad else texel[3])
            uv.append((u & 0xffffffff, v & 0xffffffff))
            spans.append(span)
            colors.append(sum(c << (8*k) for k, c in enumerate(color)))
            depths.append(depth)
            rgba.append((result, texel[3] != 0))
        x, y = (j * 4) & 65535, case_id & 65535
        def lanes(values, width):
            return sum(value << (lane * width) for lane, value in enumerate(values))
        fields = [(x,16),(y,16),(mask,4),(int(quad),1),
                  (lanes([a[0] for a in uv],32),128),
                  (lanes([a[1] for a in uv],32),128),
                  (lanes(spans,96),384),(lanes(depths,16),64),
                  (lanes(colors,24),96),(sample_group,4),(alpha,8)]
        record, shift = 0, 0
        for value, width in fields:
            record |= value << shift
            shift += width
        samples.append(f'{record:0240x}\n')
        emask = sum(((mask >> lane) & 1) * int(rgba[lane][1]) << lane for lane in range(4))
        ecolor = lanes([sum(c << (8*k) for k, c in enumerate(r[0][:3])) for r in rgba],24)
        ealpha = lanes([r[0][3] for r in rgba],8)
        expected.append(f'{(x | y<<16 | emask<<32 | lanes(depths,16)<<36 | ecolor<<100 | ealpha<<196):057x}\n')
(out / 'cases.hex').write_text(''.join(headers))
(out / 'samples.hex').write_text(''.join(samples))
(out / 'expected.hex').write_text(''.join(expected))
(out / 'counts.txt').write_text(f'{len(cases)} {len(samples)}\n')
print(f'Generated {len(cases)} cases, {len(samples)} groups from texture.py')
