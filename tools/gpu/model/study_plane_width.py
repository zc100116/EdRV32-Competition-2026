#!/usr/bin/env python3
"""study_plane_width.py — gpu-spec 2.13 precision reduction experiment.
Round setup coefficients; sweep B/P and analytic versus 2x2 difference LOD.
Host standard-library study, seed 20261124; no clock domain.
"""
import argparse
import itertools
import json
from pathlib import Path
import resource
import time

from study_v03 import (GPU, Ideal, ScreenIdeal, Memory, Metrics, FilterMetrics,
                       corpus, screen_cases, fixed_fragments, texture_levels,
                       float_filter, interleave_texture, costs)
from tools.gpu.model.arithmetic import edge, logarithm, saturate, shift
from tools.gpu.model.planes import PixelArithmetic
from tools.gpu.model.texture import Texture

Q_DROPS = (0, 4, 16, 20)
Z_DROPS = (0, 8)
C_DROPS = (0, 12)
# name, q-only vertex bits, mantissa bits, quad LOD, q drop, Z drop, RGB drop.
SCENARIOS = (('A', 32, 18, False, 0, 0, 0),
             ('B', 32, 18, False, 16, 8, 12),
             ('C', 32, 16, False, 16, 8, 12),
             ('D', 32, 16, True, 16, 8, 12),
             ('E', 32, 16, True, 20, 8, 12),
             ('F', 24, 16, True, 16, 8, 12),
             ('G', 32, 18, False, 4, 8, 12),
             ('H', 32, 18, False, 0, 8, 12),
             ('G2', 32, 18, True, 4, 8, 12),
             ('G3', 32, 16, True, 4, 8, 12))


def signed_width(bound):
    return bound.bit_length() + 1


def conservative_width(drop, bits=32):
    # s12.4: origin-to-vertex deltas <4096 per axis; origin >= -2048.
    # Screen including a four-lane group's final step: dx<=2688, dy<=2408.
    # Existing signed-56 coefficients, B32 vertices; nearest rounding included.
    coefficient = shift(1 << (bits + 23), drop)
    bound = shift(1 << bits, drop) + (8192 + 2688 + 2408) * coefficient + 1
    return signed_width(bound)


class UndefinedQ(ArithmeticError):
    """A sampled perspective coordinate has no reciprocal after quantization."""


class Reduced(PixelArithmetic):
    DROPS = (0,) * 7
    MODE = 'q'
    QUAD = False
    widths = [0] * 7

    def __init__(self, vertices, area):
        super().__init__(vertices, area)
        if self.PLANE_BITS != 32:
            fixed = PixelArithmetic(vertices, area)
            for c in (0, 4, 5, 6):
                self.coefficients[c] = fixed.coefficients[c]
                self.exponents[c] = fixed.exponents[c]
        self.coefficients = [tuple(shift(v, d) for v in coeff)
                             for coeff, d in zip(self.coefficients, self.DROPS)]
        self.exponents = [e + d for e, d in zip(self.exponents, self.DROPS)]
        self.gradients = [[self.normal(self.coefficients[c][axis], self.exponents[c])
                           for c in (1, 2, 3)] for axis in (1, 2)]
        for c, coeff in enumerate(self.coefficients):
            bound = max(abs(v) for v in coeff)
            for x, y in itertools.product((0, 640), (0, 360)):
                bound = max(bound, abs(self.at(x, y)[c]))
            self.widths[c] = max(self.widths[c], signed_width(bound))

    def coordinates(self, attrs):
        q, uq, vq = [self.normal(attrs[c], self.exponents[c]) for c in (1, 2, 3)]
        # Helper pixels extrapolate outside coverage, so q can have either sign.
        magnitude, exponent = q
        if magnitude == 0:
            raise UndefinedQ('2x2 UV evaluation has zero interpolated q after rounding')
        w = self.inverse((abs(magnitude), exponent))
        if magnitude < 0:
            w = -w[0], w[1]
        return [self.multiply(value, w) for value in (uq, vq)]

    def shade(self, attrs):
        if self.MODE == 'q' and not self.QUAD:
            return super().shade(attrs)
        if self.QUAD:
            uv = self.coordinates(attrs)
            coordinates = [shift(v, -e - 8) for v, e in uv]
            return 0, *coordinates, 0, [0, 0, 0]
        depth = saturate(shift(attrs[0], -self.exponents[0]), 0, 65535)
        colors = [saturate(shift(attrs[c], -self.exponents[c]), 0, 255)
                  for c in (4, 5, 6)]
        return depth, 0, 0, 0, colors


class StudyGPU(GPU):
    def fragments(self, vertices):
        if not self._pixel_arithmetic.QUAD:
            yield from super().fragments(vertices)
            return
        a, b, c = vertices
        area = edge(a, b, c[0], c[1])
        if area < 0:
            b, c, area = c, b, -area
        if area == 0:
            return
        arithmetic = self._pixel_arithmetic((a, b, c), area)
        row = None
        cache = {}
        for x, y, _, u, v, _, _ in super().fragments(vertices):
            if row != y // 2:
                cache.clear()
                row = y // 2
            key = x // 2
            if key not in cache:
                uv = [arithmetic.coordinates(arithmetic.at(xx, yy))
                      for yy in (y & ~1, (y & ~1) + 1)
                      for xx in (x & ~1, (x & ~1) + 1)]
                span = 0
                for i, j in ((0, 1), (2, 3), (0, 2), (1, 3)):
                    for channel in (0, 1):
                        value, exponent = arithmetic.subtract(uv[j][channel], uv[i][channel])
                        span = max(span, shift(abs(value), -exponent - 16))
                cache[key] = logarithm(span) if span else 0
            attrs = arithmetic.at(x, y)
            depth = saturate(shift(attrs[0], -arithmetic.exponents[0]), 0, 65535)
            colors = [saturate(shift(attrs[c], -arithmetic.exponents[c]), 0, 255)
                      for c in (4, 5, 6)]
            yield x, y, depth, u, v, cache[key], colors


def step_test():
    vertices = [[-173, -91, 17, 1 << 29, 19 << 29, 43 << 29, *([77 << 16] * 3)],
                [2013, 83, 65535, 1 << 26, 23117 << 26, 46534 << 26,
                 *([199 << 16] * 3)],
                [119, 3309, 19283, 1 << 23, 46253 << 23, 27533 << 23,
                 *([13 << 16] * 3)]]
    area = edge(*vertices[:2], *vertices[2][:2])
    for d in sorted(set(Q_DROPS + Z_DROPS + C_DROPS)):
        cls = type('Step', (Reduced,), dict(DROPS=(d,) * 7, widths=[0] * 7))
        plane = cls(vertices, area)
        row = plane.at(-20, -11)
        for y in range(-11, 241):
            assert row == plane.at(-20, y)
            lanes = [plane.at(-20 + lane, y) for lane in range(4)]
            for group in range(-20, 144, 4):
                for lane in range(4):
                    assert lanes[lane] == plane.at(group + lane, y)
                    lanes[lane] = [v + 4 * c[1] for v, c in
                                   zip(lanes[lane], plane.coefficients)]
            row = [v + c[2] for v, c in zip(row, plane.coefficients)]


def compose(q, z, c):
    result = dict(q)
    for key in ('max', 'rms'):
        result[key] = [q[key][0], z[key][1], q[key][2], c[key][3]]
    return result


def estimate(widths, precision=18, quad=False):
    z, q, c = widths
    # Generalize study_v03's 56W accumulation + 48W normalization terms.
    saving = 8 * ((70 - z) + 3 * (70 - q) + 3 * (70 - c)) + 48 * (70 - q)
    baseline = costs(32, 18)
    # Depth/RGB retain B32, so the shared setup multiplier pools still need B32.
    cost = costs(32, precision)
    lut = cost['lut'] - saving
    blocks = ((precision + 17) // 18) ** 2
    apm = cost['apm'] - (16 * blocks if quad else 0)
    if quad:
        lut -= 16 * (6 * precision + 48)
        lut += 8 * (precision + 4) * 2
    return dict(lut=lut, lut_delta=lut - baseline['lut'], apm=apm,
                apm_delta=apm - baseline['apm'],
                ff_saved_per_seven_attribute_register_bank=(
                    (70 - z) + 3 * (70 - q) + 3 * (70 - c)),
                ff_saved_per_q_triplet_register_bank=3 * (70 - q))


def scan(profiles, auxiliary=True):
    matrix = (255, 0, 0, 0, 0, 261, 0, 0, 0, 0, 128, -655, 0, 0, 256, 0)
    light = dict(LX=6000, LY=-4000, LZ=14700, AMB_RGB=0x202830, DIR_RGB=0xe0c090)
    levels = texture_levels()
    engines = {}
    variants = [('q', profile) for profile in profiles]
    if auxiliary:
        variants += [('z', d) for d in Z_DROPS if d]
        variants += [('c', d) for d in C_DROPS if d]
    for kind, parameter in variants:
        bits, precision, quad, d = parameter if kind == 'q' else (32, 18, False, parameter)
        drops = tuple(d if (kind == 'q' and i in (1, 2, 3)
                           or kind == 'z' and i == 0 or kind == 'c' and i >= 4)
                      else 0 for i in range(7))
        cls = type('Candidate', (Reduced,), dict(DROPS=drops, MODE=kind, widths=[0] * 7,
                                      PLANE_BITS=bits, MANTISSA_BITS=precision, QUAD=quad))
        gpu = StudyGPU(Memory(0, b''), reference_size=(640, 360))
        gpu._pixel_arithmetic = cls
        gpu.matrix, gpu.light, gpu.pixel_state = matrix, light, {'CULL': 0}
        gpu.target = dict(TGT_X0=0, TGT_Y0=0, SC_X0=0, SC_Y0=0, SC_X1=640, SC_Y1=360,
                          VP_X0=0, VP_Y0=0, VP_W=640, VP_H=360)
        gpu.ram[:] = interleave_texture(levels, 256, 256, 2)
        gpu.texture = Texture(gpu.ram, gpu.palettes,
                              dict(LOG2_W=8, LOG2_H=8, LEVELS=9, FORMAT=2,
                                   OFFSET=0, SAMPLE=2, PAL_GROUP=0, LOD_BIAS=0))
        engines[kind, parameter] = gpu
    totals = {key: Metrics() for key in variants}
    deltas = {key: Metrics() for key in variants}
    filters = {profile: FilterMetrics() for profile in profiles}
    filter_deltas = {profile: FilterMetrics() for profile in profiles}
    cases = [(n, v, False) for n, v in corpus()]
    cases += [(n, v, True) for n, v in screen_cases()]
    invalid = {}
    for scene, vertices, screen in cases:
        ideal = (ScreenIdeal if screen else Ideal)(matrix, light).fragments(vertices)
        baseline = fixed_fragments(engines['q', (32, 18, False, 0)], vertices, screen)
        if screen:
            float_colors = {p: float_filter(f, levels) for p, f in ideal.items()}
            fixed_colors = {p: engines['q', (32, 18, False, 0)].texture.sample(
                round(f[0] * 256), round(f[1] * 256), round(f[3] * 256))
                for p, f in baseline.items()}
        for key, gpu in engines.items():
            if key in invalid:
                continue
            try:
                fixed = (baseline if key == ('q', (32, 18, False, 0))
                         else fixed_fragments(gpu, vertices, screen))
            except UndefinedQ as error:
                invalid[key] = f'{scene}: {error}'
                print(f'INVALID {key}: {invalid[key]}', flush=True)
                continue
            # Z/RGB variants do not affect UV, LOD or texture filtering.
            if key[0] != 'q':
                fixed = {p: (baseline[p][0], baseline[p][1], f[2], baseline[p][3], *f[4:])
                         for p, f in fixed.items()}
            totals[key].add(fixed, ideal)
            deltas[key].add(fixed, baseline)
            if screen and key[0] == 'q':
                for p, f in fixed.items():
                    sampled = gpu.texture.sample(round(f[0] * 256), round(f[1] * 256),
                                                 round(f[3] * 256))
                    if p in float_colors:
                        filters[key[1]].add(sampled, float_colors[p])
                    if p in fixed_colors:
                        filter_deltas[key[1]].add(sampled, fixed_colors[p])
    return engines, totals, deltas, filters, filter_deltas, invalid


def passes(delta, filtered):
    return (delta['coverage_xor'] == 0 and delta['max'][0] <= 1 / 16
            and delta['rms'][0] <= 1 / 64
            and delta['max'][1] <= 4 and delta['max'][3] <= 1
            and delta['mip_different_percent'] <= .1
            and filtered[0] <= 3 and filtered[1] <= .5)


def assemble(scenario, data, auxiliary):
    name, bits, precision, quad, q, z, c = scenario
    engines, totals, deltas, filters, filter_deltas, invalid = data
    profile = bits, precision, quad, q
    qkey = 'q', profile
    widths = [conservative_width(z), conservative_width(q, bits), conservative_width(c)]
    if qkey in invalid:
        return dict(name=name, bits=bits, precision=precision,
                    lod='quad' if quad else 'analytic', drops_q_z_rgb=[q, z, c],
                    widths_z_q_rgb=widths, measured_widths_z_q_rgb=None,
                    v03_delta=None, float=None, trilinear_v03_max_rms=None,
                    trilinear_float_max_rms=None, cost=estimate(widths, precision, quad),
                    passes=False, invalid_reason=invalid[qkey])
    az, ac = auxiliary[z, 0], auxiliary[0, c]
    delta = compose(deltas[qkey].result(), az['v03_delta'], ac['v03_delta'])
    ideal = compose(totals[qkey].result(), az['float'], ac['float'])
    measured = [az['measured_widths_z_q_rgb'][0],
                max(engines[qkey]._pixel_arithmetic.widths[1:4]),
                ac['measured_widths_z_q_rgb'][2]]
    filtered = filter_deltas[profile].result()
    return dict(name=name, bits=bits, precision=precision, lod='quad' if quad else 'analytic',
                drops_q_z_rgb=[q, z, c], widths_z_q_rgb=widths,
                measured_widths_z_q_rgb=measured, v03_delta=delta, float=ideal,
                trilinear_v03_max_rms=filtered,
                trilinear_float_max_rms=filters[profile].result(),
                cost=estimate(widths, precision, quad), passes=passes(delta, filtered))


def run(reuse=None, case=None):
    start = time.perf_counter()
    step_test()
    selected = [s for s in SCENARIOS if case is None or s[0] == case]
    profiles = list(dict.fromkeys([(32, 18, False, 0)]
                                 + [tuple(s[1:5]) for s in selected]))
    data = scan(profiles, auxiliary=reuse is None)
    engines, totals, deltas, _, _, _ = data
    auxiliary = {}
    if reuse is not None:
        cached = json.loads(reuse.read_text())
        for z, c in ((0, 0), (8, 0), (0, 12), (8, 12)):
            auxiliary[z, c] = next(a for a in cached if a['bits'] == 32
                                   and a['precision'] == 18 and a['lod'] == 'analytic'
                                   and a['drops_q_z_rgb'] == [0, z, c])
    else:
        for z, c in ((0, 0), (8, 0), (0, 12)):
            key = ('z', z) if z else ('c', c) if c else ('q', (32, 18, False, 0))
            auxiliary[z, c] = dict(v03_delta=deltas[key].result(), float=totals[key].result(),
                                   measured_widths_z_q_rgb=[
                                       engines[key]._pixel_arithmetic.widths[0],
                                       max(engines[key]._pixel_arithmetic.widths[1:4]),
                                       max(engines[key]._pixel_arithmetic.widths[4:])])
    results = []
    for scenario in selected:
        name = scenario[0]
        if reuse is not None and name in ('A', 'H'):
            z, c = scenario[-2:]
            result = dict(auxiliary[z, c], name=name)
        else:
            result = assemble(scenario, data, auxiliary)
        results.append(result)
        print(json.dumps(result), flush=True)
    result = dict(seed=20261124, source_triangles=len(corpus()), triangles=len(corpus()) + 4,
                  metrics_order=['uv_texels', 'depth_u16', 'lod_levels', 'color_u8'],
                  variants=results, reused_summaries=sum(
                      reuse is not None and s[0] in ('A', 'H') for s in selected),
                  step_test='PASS', seconds=time.perf_counter() - start,
                  max_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    if case is None:
        result.update(choose(results))
    return result


def choose(results):
    passing = [r for r in results if r['passes']]
    recommended = min(passing, key=lambda r: (r['cost']['apm'], r['cost']['lut'],
                      sum(a * b for a, b in zip(r['widths_z_q_rgb'], (1, 3, 3)))))
    cheaper = [r for r in results if r['cost']['lut'] < recommended['cost']['lut']
               and r['cost']['apm'] <= recommended['cost']['apm']]
    def violation(r):
        if 'invalid_reason' in r:
            return float('inf')
        d = r['v03_delta']
        f = r['trilinear_v03_max_rms']
        return max(d['max'][0] * 16, d['rms'][0] * 64, d['max'][1] / 4,
                   d['max'][3], d['mip_different_percent'] / .1, f[0] / 3, f[1] / .5)
    next_smaller = min(cheaper, key=lambda r: (violation(r), r['cost']['lut']))
    return dict(recommended=recommended, next_smaller=next_smaller)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/gpu/study-plane-width.json'))
    parser.add_argument('--reuse', type=Path, help='Completed intermediate JSON rows to reuse')
    parser.add_argument('--case', choices=[s[0] for s in SCENARIOS],
                        help='Run one point for parallel remote execution')
    args = parser.parse_args()
    result = run(args.reuse, args.case)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    if 'recommended' in result:
        print('recommended', json.dumps(result['recommended']))
    print(f"study: {result['seconds']:.3f}s, RSS {result['max_rss_kib']} KiB")


if __name__ == '__main__':
    main()
