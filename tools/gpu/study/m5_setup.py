#!/usr/bin/env python3
"""m5_setup.py — M-4 §3.4 / M-5 four-multiplier local block-floating study.
Host fixed-width setup, explicit DAG scheduling and current P-A comparison.
No RTL or clock domain; geometry uses exact translated integer edge products.
"""
from collections import Counter
from dataclasses import dataclass
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.gpu.model.arithmetic import divide, edge, logarithm, shift, top_left
from tools.gpu.model.planes import PixelArithmetic


@dataclass(frozen=True)
class BF:
    m: int
    e: int


def normal(m, e=0, bits=48):
    if m == 0:
        return BF(0, 0)
    amount = abs(m).bit_length() - (bits-1)
    value = shift(m, amount)
    if abs(value) >= 1 << (bits-1):
        amount += 1
        value = shift(m, amount)
    assert -(1 << (bits-1)) <= value < (1 << (bits-1))
    return BF(value, e+amount)


def plus(a, b):
    if a.m == 0:
        return b
    if b.m == 0:
        return a
    e = max(a.e, b.e)-3
    return normal(shift(a.m, e-a.e) + shift(b.m, e-b.e), e)


def times(a, b):
    assert -(1 << 48) <= a.m < (1 << 48)
    assert -(1 << 32) <= b.m < (1 << 32)
    return normal(a.m*b.m, a.e+b.e)


def inverse_area(area):
    exponent = area.bit_length()-1
    m = shift(area, exponent-31)
    if m == 1 << 32:
        m >>= 1
        exponent += 1
    index = (m-(1 << 31)) >> 21
    midpoint = (1 << 31) + (index << 21) + (1 << 20)
    y = divide(1 << 62, midpoint)
    for _ in range(2):
        y = shift(y * ((2 << 31) - shift(m*y, 31)), 31)
    return BF(y, -31-exponent)


def coefficients(vertices, values, origin, bits=32):
    """48-bit signed working mantissas, 32-bit inverse, signed output triplet.
    Subtract full 48x32 products before normalization to retain cancellation bits.
    64x64 local evaluation has a signed (bits+7)-bit accumulator.
    """
    a, b, c = vertices
    area = edge(a, b, *c)
    inv = inverse_area(area)
    attrs = [normal(v) for v in values]
    e = max(v.e for v in attrs)
    v0, v1, v2 = [shift(v.m, e-v.e) for v in attrs]
    d1, d2 = v1-v0, v2-v0
    dx1, dy1 = b[0]-a[0], b[1]-a[1]
    dx2, dy2 = c[0]-a[0], c[1]-a[1]
    # Coordinate differences are Q4; gradients are per pixel.
    assert all(-(1 << 48) <= d < (1 << 48) for d in (d1, d2))
    assert all(-(1 << 32) <= d < (1 << 32) for d in (dx1, dy1, dx2, dy2))
    numerators = (d1*dy2-d2*dy1, dx1*d2-dx2*d1)
    assert all(-(1 << 81) <= n < (1 << 81) for n in numerators)
    gx, gy = [times(normal(n, e+4), inv) for n in numerators]
    ox, oy = origin
    sx, sy = 16*ox+8-a[0], 16*oy+8-a[1]
    start = plus(BF(v0, e), plus(times(gx, BF(sx, -4)), times(gy, BF(sy, -4))))
    common = max(v.e + abs(v.m).bit_length() for v in (start, gx, gy)) - (bits-1)
    fields = tuple(shift(v.m, common-v.e) for v in (start, gx, gy))
    if max(map(abs, fields)) >= 1 << (bits-1):
        common += 1
        fields = tuple(shift(v.m, common-v.e) for v in (start, gx, gy))
    assert all(-(1 << (bits-1)) <= v < (1 << (bits-1)) for v in fields)
    assert -(1 << 9) <= common < (1 << 9)
    return fields, common


def evaluate(record, origin, x, y, bits=32):
    (s, gx, gy), e = record
    value = s+(x-origin[0])*gx+(y-origin[1])*gy
    assert -(1 << (bits+6)) <= value < (1 << (bits+6))
    return math.ldexp(value, e)


def dag(attributes, slots=4):
    """ASAP static DAG, 4x(49x33) pool, four live attributes, one packed write/cycle.
    An attribute owns a RAM slot from read through packed coefficient write.
    Same-cycle resource caps: 4 multipliers, 2 adders, 2 normalizers, 1 RAM write.
    """
    nodes = []

    def add(name, kind, deps=(), group=-1):
        nodes.append((name, kind, tuple(deps), group))
        return name

    area0 = add('area0', 'mul')
    area1 = add('area1', 'mul')
    area = add('area', 'add', (area0, area1))
    seed = add('seed', 'norm', (area,))
    reciprocal = seed
    for j in range(2):
        p = add(f'newton{j}p', 'mul', (reciprocal, seed))
        q = add(f'newton{j}q', 'add', (p,))
        reciprocal = add(f'newton{j}y', 'mul', (q, reciprocal))
    for a in range(attributes):
        tag = f'a{a}_'
        previous = (f'a{a-slots}_write',) if a >= slots else ()
        read = add(tag+'read', 'read', previous, a)
        aligned = [add(tag+f'input{i}', 'norm', (read,), a) for i in range(3)]
        diffs = [add(tag+f'd{i}', 'add', aligned, a) for i in range(2)]
        products = [add(tag+f'p{i}', 'mul', (diffs[i%2],), a) for i in range(4)]
        numerators = [add(tag+f'n{i}', 'add', products[2*i:2*i+2], a)
                      for i in range(2)]
        norms = [add(tag+f'norm{i}', 'norm', (numerators[i],), a) for i in range(2)]
        scaled = [add(tag+f'scale{i}', 'mul', (norms[i], reciprocal), a)
                  for i in range(2)]
        gradients = [add(tag+f'g{i}', 'norm', (scaled[i],), a) for i in range(2)]
        local = [add(tag+f'local{i}', 'mul', (gradients[i],), a) for i in range(2)]
        local_norm = [add(tag+f'ln{i}', 'norm', (local[i],), a) for i in range(2)]
        total = add(tag+'sum', 'add', local_norm, a)
        total_norm = add(tag+'sum_norm', 'norm', (total,), a)
        start = add(tag+'start', 'add', (total_norm, read), a)
        start_norm = add(tag+'start_norm', 'norm', (start,), a)
        packed = [add(tag+f'pack{i}', 'norm', (start_norm, *gradients), a)
                  for i in range(3)]
        add(tag+'write', 'write', packed, a)
    return nodes


def schedule(attributes):
    nodes = dag(attributes)
    latencies = dict(mul=6, add=2, norm=2, read=1, write=1)
    ports = dict(mul=4, add=2, norm=2, read=1, write=1)
    ready, issued, t = {}, [], 0
    while len(ready) < len(nodes):
        used = Counter()
        for name, kind, deps, group in nodes:
            if name in ready or used[kind] == ports[kind]:
                continue
            if all(d in ready and ready[d] <= t for d in deps):
                ready[name] = t+latencies[kind]
                used[kind] += 1
                issued.append((t, name, kind))
        t += 1
    return dict(cycles=max(ready.values()), multiplications=sum(
        kind == 'mul' for _, kind, _, _ in nodes), trace=issued,
                packed_ram_write_lower_bound=attributes,
                multiplier_lower_bound=math.ceil((8*attributes+6)/4))


def lod(uv):
    span = max(abs(uv[b][c]-uv[a][c]) for a, b in ((0, 1), (2, 3), (0, 2), (1, 3))
               for c in (0, 1))
    return max(0., min(8., math.log2(span))) if span else 0.


def summary(pairs):
    # Same units and max/RMS convention as tools/gpu/model/study_v03.py Metrics.
    return dict(max=max(abs(a-b) for a, b in pairs),
                rms=math.sqrt(sum((a-b)**2 for a, b in pairs)/len(pairs)), n=len(pairs))


def corpus():
    rng = random.Random(20261127)
    # Exact translated Q4 edges; area is the signed determinant, not half-area.
    cases = [
        ('area1', [(8, 8), (9, 8), (8, 9)]),
        ('area_pixel1', [(8, 8), (24, 8), (8, 40)]),
        ('near_collinear', [(8, 8), (16008, 16007), (16009, 16008)]),
        ('large_cancel', [(2**30+8, 2**30+8), (2**30+1032, 2**30+9),
                          (2**30+9, 2**30+1032)]),
        ('block_boundary', [(1000, 1000), (2088, 1016), (1016, 2088)]),
        ('thin', [(8, 8), (16008, 9), (16008, 10)]),
        ('two_denominators', [(8, 8), (2048, 24), (24, 2048)]),
    ]
    for i in range(32):
        x, y = rng.randrange(0, 500)*16, rng.randrange(0, 250)*16
        cases.append((f'random{i}', [(x+8, y+8), (x+rng.randrange(1, 100)*16, y+9),
                                    (x+9, y+rng.randrange(1, 100)*16)]))
    return cases


def precision(coefficient_fn=coefficients, evaluate_fn=evaluate, boundaries=False):
    cases = corpus()
    collected, per_case, quantized, in_domain = {}, {}, {}, {}
    common = {}
    continuity = {24: 0., 32: 0.}
    for name, vertices in cases:
        area = edge(vertices[0], vertices[1], *vertices[2])
        assert area > 0, name
        # Construct old-model raw formats; extra A uses the same plane path as RGB.
        raw = []
        for i, p in enumerate(vertices):
            q = round(2**30 / (1, 1.25, 2)[i])
            u, v = ((512, 1024), (61440, 256), (256, 57344))[i]
            raw.append([*p, (1000, 64000, 24000)[i], q, u*q, v*q,
                        *[c*65536 for c in ((20, 80, 160), (220, 20, 80), (80, 240, 20))[i]]])
        # Include vertices/centroid as coefficient probes even if there is no covered pixel.
        probes = [(p[0]//16, p[1]//16) for p in vertices]
        probes.append((sum(p[0] for p in vertices)//48, sum(p[1] for p in vertices)//48))
        minx, maxx = min(p[0] for p in vertices)//16, max(p[0] for p in vertices)//16
        miny, maxy = min(p[1] for p in vertices)//16, max(p[1] for p in vertices)//16
        # Bounded 9x9 scan, including exact integer edge coverage where it exists.
        for y in range(miny, maxy+1, max(1, (maxy-miny)//8)):
            for x in range(minx, maxx+1, max(1, (maxx-minx)//8)):
                weights = [edge(vertices[j], vertices[(j+1)%3], 16*x+8, 16*y+8)
                           for j in range(3)]
                if min(weights) >= 0:
                    probes.append((x, y))
        if boundaries:
            for bx in range((minx//64+1)*64, maxx+1, 64):
                for by in range(miny//64*64, maxy+1, 64):
                    probes.extend((bx+dx, by+dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
        probes = list(dict.fromkeys(probes))
        metrics = {model: {k: [] for k in ('uv', 'z', 'rgba', 'lod')}
                   for model in ('P-A', 'block24', 'block32')}
        quant_metrics = {model: {k: [] for k in ('uv', 'z', 'rgba', 'lod')}
                         for model in metrics}
        for texture in range(2):
            current = [v[:] for v in raw]
            for i, v in enumerate(current):
                v[3] *= (1, 2, 4)[i] if texture else 1
                if texture:
                    v[4], v[5] = v[5], -v[4]
            pa = PixelArithmetic(current, area)
            # Fourth color is tested using a second current RGB instance, no invented alpha RTL.
            alpha_raw = [v[:6]+[a*65536]*3 for v, a in zip(current, (32, 200, 128))]
            alpha_pa = PixelArithmetic(alpha_raw, area)
            channels = [[v[k] for v in current] for k in range(2, 9)]
            channels.append([v[6] for v in alpha_raw])

            def exact(x, y):
                # Divide the integer barycentric numerator once, avoiding large global doubles.
                w = [edge(vertices[1], vertices[2], 16*x+8, 16*y+8),
                     edge(vertices[2], vertices[0], 16*x+8, 16*y+8),
                     edge(vertices[0], vertices[1], 16*x+8, 16*y+8)]
                return [sum(ww*vv for ww, vv in zip(w, ch))/area for ch in channels]

            def projected(attrs):
                return [attrs[2]/attrs[1]/256, attrs[3]/attrs[1]/256]

            def output(attrs):
                return [min(65535., max(0., attrs[0])),
                        *[min(255., max(0., c/65536)) for c in attrs[4:]]]

            records = {}

            def block(x, y, bits):
                origin = x//64*64, y//64*64
                key = origin, bits
                if key not in records:
                    records[key] = [coefficient_fn(vertices, ch, origin, bits) for ch in channels]
                return [evaluate_fn(r, origin, x, y, bits) for r in records[key]]

            for x, y in probes:
                ideal = exact(x, y)
                quad = [(x & ~1, y & ~1), ((x & ~1)+1, y & ~1),
                        (x & ~1, (y & ~1)+1), ((x & ~1)+1, (y & ~1)+1)]
                pa_value = pa.shade(pa.at(x, y))
                pa_out = [pa_value[0], *pa_value[4], alpha_pa.shade(alpha_pa.at(x, y))[4][0]]
                pa_uv = [pa_value[1]/256, pa_value[2]/256]
                pa_span = pa.quad_span(x, y)
                pa_lod = max(0., min(8., logarithm(pa_span)/256)) if pa_span else 0.
                ideal_lod = lod([projected(exact(xx, yy)) for xx, yy in quad])
                for model in metrics:
                    if model == 'P-A':
                        uv, color, level = pa_uv, pa_out, pa_lod
                    else:
                        bits = int(model[5:])
                        attrs = block(x, y, bits)
                        uv, color = projected(attrs), output(attrs)
                        level = lod([projected(block(xx, yy, bits)) for xx, yy in quad])
                    m = metrics[model]
                    m['uv'].extend(zip(uv, projected(ideal)))
                    m['z'].append((color[0], output(ideal)[0]))
                    m['rgba'].extend(zip(color[1:], output(ideal)[1:]))
                    m['lod'].append((level, ideal_lod))
                    qm = quant_metrics[model]
                    # Match current integer Z/RGBA and Q8 UV readout; LOD is reported
                    # internally before sampler level selection for both models.
                    quv = uv if model == 'P-A' else [
                        math.copysign(math.floor(abs(v)*256+.5), v)/256 for v in uv]
                    qc = color if model == 'P-A' else [math.floor(v+.5) for v in color]
                    qm['uv'].extend(zip(quv, projected(ideal)))
                    qm['z'].append((qc[0], output(ideal)[0]))
                    qm['rgba'].extend(zip(qc[1:], output(ideal)[1:]))
                    qm['lod'].append((level, ideal_lod))
                    covered = all(edge(vertices[j], vertices[(j+1)%3],
                                       16*x+8, 16*y+8) >=
                                  (0 if top_left(vertices[j], vertices[(j+1)%3]) else 1)
                                  for j in range(3))
                    if covered and 0 <= x < 640 and 0 <= y < 360:
                        cm = common.setdefault(model, {k: [] for k in qm})
                        cm['uv'].extend(zip(quv, projected(ideal)))
                        cm['z'].append((qc[0], output(ideal)[0]))
                        cm['rgba'].extend(zip(qc[1:], output(ideal)[1:]))
                        cm['lod'].append((level, ideal_lod))
            # Quantization continuity: same boundary sample evaluated from either tile record.
            bx = ((minx+maxx)//2//64+1)*64
            by = (miny+maxy)//2//64*64
            for bits in (24, 32):
                for ch in channels:
                    a = coefficient_fn(vertices, ch, (bx-64, by), bits)
                    b = coefficient_fn(vertices, ch, (bx, by), bits)
                    left = evaluate_fn(a, (bx-64, by), bx, by, bits)
                    right = evaluate_fn(b, (bx, by), bx, by, bits)
                    continuity[bits] = max(continuity[bits], abs(left-right)/max(1., abs(right)))
        per_case[name] = {model: {k: summary(v) for k, v in row.items()}
                          for model, row in metrics.items()}
        for model, row in metrics.items():
            dst = collected.setdefault(model, {k: [] for k in row})
            for k, v in row.items():
                dst[k].extend(v)
        for model, row in quant_metrics.items():
            dst = quantized.setdefault(model, {k: [] for k in row})
            dom = in_domain.setdefault(model, {k: [] for k in row})
            for k, v in row.items():
                dst[k].extend(v)
                if name != 'large_cancel':
                    dom[k].extend(v)
    return dict(seed=20261127, triangles=len(cases), texture_sets=2,
                aggregate={m: {k: summary(v) for k, v in row.items()}
                           for m, row in collected.items()}, per_case=per_case,
                quantized={m: {k: summary(v) for k, v in row.items()}
                           for m, row in quantized.items()},
                bounded_coordinate_quantized={m: {k: summary(v) for k, v in row.items()}
                                     for m, row in in_domain.items()},
                common_covered_quantized={m: {k: summary(v) for k, v in row.items()}
                                          for m, row in common.items()},
                max_boundary_relative_jump=continuity,
                scope='covered samples plus explicit vertex/centroid coefficient probes')


def resources():
    # Lifetime ledger, external FF only: APM internal pipeline registers excluded.
    registers = {
        'pool_product_combine_4x3x82': 4*3*82,
        'cascade_low16_4x3x3x16': 4*3*3*16,
        'pool_tags_4x6x16': 4*6*16,
        'normalizers_2x2x92': 2*2*92,
        'adders_2x2x82': 2*2*82,
        'local_scratch_4x(3x48+32)': 4*(3*48+32),
        'geometry_deltas_4x32_area65': 4*32+65,
        'reciprocal_state_3x32': 3*32,
        'record_output_3x32_exp10': 3*32+10,
        'control_counters_valid': 160,
    }
    ff = sum(registers.values())
    # LUT estimates: exact inputs, no PDS inference claimed. LUTRAM is a LUT subset.
    luts = dict(product_combine=4*164, adders_align=2*(82*7+82),
                normalize_shift=2*(82*7+48), exponent_control=400,
                controller_address=450, lutram=512+3*58+8*92)
    vector = [sum(luts.values()), ff, 4*6, 2, luts['lutram']]
    return dict(register_bits=registers, luts=luts, vector=vector,
                clm=math.ceil(max(vector[0]/4, ff/8)/.70),
                ram_fields=dict(input_vertices=3*16*(48+10),
                                attribute_scratch=4*(2*(82+10)+2*(48+10)+48+10),
                                triangle_record_double_buffer=2*16*(3*32+10),
                                seed_rom=1024*32),
                apm_formula='4 pools * ceil(49/24)*ceil(33/17) = 24 APM',
                note='2 DRM records; scratch has 2 async 92-bit banks per context; +/-40%')
