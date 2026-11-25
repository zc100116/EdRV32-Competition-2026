#!/usr/bin/env python3
"""study_v03.py — gpu-spec v0.3 proposal, deterministic per-pixel width study.
Host standard-library experiment; seed and full M-1 corpus retained, no clock domain.
The historical v0.2 exact fragment path lives only in this disposable study.
"""
import argparse
import json
import math
from pathlib import Path
import random
import resource
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.gpu.model import GPU, interleave_texture
from tools.gpu.model.arithmetic import (RECIPROCAL_FRAC, divide, edge, expand, logarithm,
                                        reciprocal, saturate, shift, top_left)
from tools.gpu.model.planes import PixelArithmetic as CurrentPixelArithmetic
from tools.gpu.scene import Memory


class PixelArithmetic(CurrentPixelArithmetic):
    """Historical v0.3 baseline, retained only for numeric experiments."""
    DROPS = (0,) * 7
    LOD_QUAD = False

    def __init__(self, vertices, area):
        super().__init__(vertices, area)
        self.gradients = [[self.normal(self.coefficients[c][axis], self.exponents[c])
                           for c in (1, 2, 3)] for axis in (1, 2)]

    def shade(self, attrs):
        depth = saturate(shift(attrs[0], -self.exponents[0]), 0, 65535)
        q, uq, vq = [self.normal(attrs[c], self.exponents[c]) for c in (1, 2, 3)]
        w = self.inverse(q)
        uv = [self.multiply(value, w) for value in (uq, vq)]
        coordinates = [shift(value, -exponent - 8) for value, exponent in uv]
        span = 0
        for dq, duq, dvq in self.gradients:
            for gradient, coordinate in zip((duq, dvq), uv):
                delta = self.subtract(gradient, self.multiply(coordinate, dq))
                value, exponent = self.multiply(delta, w)
                span = max(span, shift(abs(value), -exponent - 16))
        lod = logarithm(span) if span else 0
        colors = [saturate(shift(attrs[c], -self.exponents[c]), 0, 255)
                  for c in (4, 5, 6)]
        return depth, *coordinates, lod, colors


class ExactGPU(GPU):
    def fragments(self, vertices):
        """Rasterize [xQ4,yQ4,depthU16,qQF,uQ8*q,vQ8*q,rQ16,gQ16,bQ16]."""
        a, b, c = vertices
        area = edge(a, b, c[0], c[1])
        cull = self.pixel_state['CULL']
        if area == 0 or (cull == 1 and area > 0) or (cull == 2 and area < 0):
            return
        if area < 0:
            b, c = c, b
            area = -area
        self.perf(2)
        x0, y0, x1, y1 = self.bounds()
        x0 = max(x0, (min(a[0], b[0], c[0]) - 8 + 15) // 16)
        y0 = max(y0, (min(a[1], b[1], c[1]) - 8 + 15) // 16)
        x1 = min(x1, (max(a[0], b[0], c[0]) - 8) // 16 + 1)
        y1 = min(y1, (max(a[1], b[1], c[1]) - 8) // 16 + 1)
        edges = ((b, c), (c, a), (a, b))
        inclusive = [top_left(start, end) for start, end in edges]
        # Attribute gradients have units of one screen pixel, with area denominator.
        dx = [(start[1] - end[1]) * 16 for start, end in edges]
        dy = [(end[0] - start[0]) * 16 for start, end in edges]
        derivatives = [[sum(weight * vertex[channel] for weight, vertex in
                            zip(weights, (a, b, c))) for channel in (3, 4, 5)]
                       for weights in (dx, dy)]
        for y in range(y0, y1):
            for group in range((x0 // 4) * 4, x1, 4):
                for x in range(max(x0, group), min(group + 4, x1)):
                    weights = [edge(start, end, x * 16 + 8, y * 16 + 8)
                               for start, end in edges]
                    if any(value < 0 or (value == 0 and not include)
                           for value, include in zip(weights, inclusive)):
                        continue
                    attrs = [divide(sum(weight * vertex[channel] for weight, vertex in
                                        zip(weights, (a, b, c))), area)
                             for channel in range(2, 9)]
                    depth, q, uq, vq = attrs[:4]
                    # The same normalized reciprocal unit is used for per-pixel correction.
                    inverse_q = reciprocal(q, RECIPROCAL_FRAC)
                    u = shift(uq * inverse_q, 2 * RECIPROCAL_FRAC)
                    v = shift(vq * inverse_q, 2 * RECIPROCAL_FRAC)
                    span = 0
                    for dq, duq, dvq in derivatives:
                        for numerator, attribute in ((duq, uq), (dvq, vq)):
                            derivative = divide(abs(numerator * q - attribute * dq) << 8,
                                                area * q * q)
                            span = max(span, derivative)
                    lod = logarithm(span) if span else 0
                    colors = [saturate(shift(value, 16), 0, 255) for value in attrs[4:]]
                    yield x, y, depth, u, v, lod, colors



class Ideal:
    """Unquantized transform, clipping, projection and rational attribute interpolation."""
    def __init__(self, matrix, light):
        self.matrix = [value / 65536 for value in matrix]
        self.light = light
        self.near = 1 / 16
        self.guard = 4

    def transform(self, vertex):
        position = [vertex[name] for name in ('X', 'Y', 'Z')] + [1]
        coords = [sum(self.matrix[row * 4 + col] * position[col] for col in range(4))
                  for row in range(4)]
        dot = max(0, sum(vertex[n] / 128 * self.light[l] / 16384 for n, l in
                         zip(('NX', 'NY', 'NZ'), ('LX', 'LY', 'LZ'))))
        colors = [min(255, color * (((self.light['AMB_RGB'] >> bit) & 255)
                                   + dot * ((self.light['DIR_RGB'] >> bit) & 255)) / 255)
                  for color, bit in zip(expand(vertex['COLOR']), (16, 8, 0))]
        return coords + [vertex['U'] / 256, vertex['V'] / 256] + colors

    def triangles(self, vertices):
        polygon = [self.transform(vertex) for vertex in vertices]
        for plane in (lambda v: v[3] - self.near, lambda v: self.guard * v[3] + v[0],
                      lambda v: self.guard * v[3] - v[0],
                      lambda v: self.guard * v[3] + v[1],
                      lambda v: self.guard * v[3] - v[1]):
            if not polygon:
                return
            output = []
            previous = polygon[-1]
            dp = plane(previous)
            for current in polygon:
                dc = plane(current)
                if (dp >= 0) != (dc >= 0):
                    output.append([(a * dc - b * dp) / (dc - dp)
                                   for a, b in zip(previous, current)])
                if dc >= 0:
                    output.append(current)
                previous, dp = current, dc
            polygon = output
        projected = []
        for vertex in polygon:
            x, y, z, w, u, v, *colors = vertex
            projected.append([(x / w + 1) * 320, (1 - y / w) * 180,
                              min(1, max(0, z / w)) * 65535, 1 / w, u / w, v / w,
                              *colors])
        for index in range(1, len(projected) - 1):
            yield projected[0], projected[index], projected[index + 1]

    def fragments(self, vertices):
        fragments = {}
        for triangle in self.triangles(vertices):
            a, b, c = triangle
            area = ((b[0] - a[0]) * (c[1] - a[1])
                    - (b[1] - a[1]) * (c[0] - a[0]))
            if area == 0:
                continue
            if area < 0:
                b, c, area = c, b, -area
            sides = ((b, c), (c, a), (a, b))
            coefficients = [(start[1] - end[1], end[0] - start[0],
                             start[0] * end[1] - start[1] * end[0])
                            for start, end in sides]
            tops = [end[1] < start[1] or (end[1] == start[1] and end[0] > start[0])
                    for start, end in sides]
            gradients = [[sum(coeff[axis] * vertex[channel] for coeff, vertex in
                              zip(coefficients, (a, b, c))) / area for channel in (3, 4, 5)]
                         for axis in (0, 1)]
            for y in range(max(0, math.ceil(min(a[1], b[1], c[1]) - 0.5)),
                           min(360, math.floor(max(a[1], b[1], c[1]) - 0.5) + 1)):
                for x in range(max(0, math.ceil(min(a[0], b[0], c[0]) - 0.5)),
                               min(640, math.floor(max(a[0], b[0], c[0]) - 0.5) + 1)):
                    weights = [cx * (x + 0.5) + cy * (y + 0.5) + const
                               for cx, cy, const in coefficients]
                    if any(weight < 0 or (weight == 0 and not include)
                           for weight, include in zip(weights, tops)):
                        continue
                    depth, q, uq, vq, *colors = [sum(weight * vertex[channel]
                                                    for weight, vertex in
                                                    zip(weights, (a, b, c))) / area
                                                for channel in range(2, 9)]
                    u, v = uq / q, vq / q
                    span = max(abs((duq * q - uq * dq) / (q * q))
                               for dq, duq, _ in gradients)
                    span = max(span, max(abs((dvq * q - vq * dq) / (q * q))
                                         for dq, _, dvq in gradients))
                    lod = max(0, min(8, math.log2(span))) if span > 0 else 0
                    fragments[(x, y)] = (u, v, depth, lod, *colors)
        return fragments


def corpus():
    rng = random.Random(20261124)
    cases = []
    def vertex(point, uv):
        return dict(zip(('X', 'Y', 'Z', 'U', 'V', 'NX', 'NY', 'NZ', 'COLOR'),
                        (*point, *uv, rng.randint(-80, 80), rng.randint(-80, 80),
                         rng.randint(40, 127), rng.choice((65535, 0xfbad, 0x7def)))))
    def triangle(name, points, uvs=((0, 0), (65535, 0), (0, 65535))):
        cases.append((name, [vertex(point, uv) for point, uv in zip(points, uvs)]))
    # A triangulated random height/depth mesh shares original vertices.
    grid = [[vertex((-240 + x * 60 + rng.randrange(-8, 9),
                     -150 + y * 50 + rng.randrange(-8, 9), rng.randrange(320, 1600)),
                    (x * 7000, y * 10000)) for x in range(9)] for y in range(7)]
    for y in range(6):
        for x in range(8):
            a, b, c, e = grid[y][x], grid[y][x + 1], grid[y + 1][x], grid[y + 1][x + 1]
            cases.extend([('mesh', [a, b, e]), ('mesh', [a, e, c])])
    # W ratio 4096/16=256: ground and wall each span the visible image.
    triangle('ground', [(-220, -12, 16), (220, -12, 16), (220, -12, 4096)])
    triangle('ground', [(-220, -12, 16), (220, -12, 4096), (-220, -12, 4096)])
    triangle('wall', [(-12, -220, 16), (-12, 220, 16), (-12, 220, 4096)])
    triangle('wall', [(-12, -220, 16), (-12, 220, 4096), (-12, -220, 4096)])
    for _ in range(32):
        x, y = rng.randrange(-5000, 5000), rng.randrange(-3000, 3000)
        triangle('far-small', [(x, y, 8192), (x + 32, y, 8192), (x, y + 32, 8192)])
    for _ in range(8):
        x, y = rng.randrange(-12, 13), rng.randrange(-12, 13)
        triangle('near-crossing', [(x, y, -4), (x + 9, y - 7, 32), (x - 5, y + 9, 48)])
    for sign in (-1, 1):
        for delta in (-1, 0, 1):
            triangle('guard-adjacent', [(sign * (256 * 4 + delta), -80, 256),
                                       (-96, -128, 256), (96, 128, 256)])
    return cases


class ScreenIdeal(Ideal):
    def triangles(self, vertices):
        yield [[v[0] / 16, v[1] / 16, v[2], v[3] / (1 << 30),
                v[4] / (1 << 38), v[5] / (1 << 38),
                *(c / 65536 for c in v[6:])] for v in vertices]


def screen_cases():
    def vertex(x, y, w, u, v):
        q = round((1 << 30) / w)
        return [x * 16, y * 16, round(65535 * (1 - 1 / (w * 32))), q,
                round(u * 256) * q, round(v * 256) * q, *([255 << 16] * 3)]
    square = [vertex(x, y, 1, x, y) for x, y in ((0, 0), (64, 0), (64, 64), (0, 64))]
    ground = [vertex(x, y, w, u, v) for x, y, w, u, v in
              ((0, 12, 32, 0, 255.99609375), (640, 12, 32, 255.99609375, 255.99609375),
               (640, 360, .125, 255.99609375, 0), (0, 360, .125, 0, 0))]
    for name, quad in (('one-to-one', square), ('perspective-trilinear', ground)):
        for i, j, k in ((0, 1, 2), (0, 2, 3)):
            yield name, [quad[i], quad[j], quad[k]]


def fixed_fragments(gpu, vertices, screen=False):
    if screen:
        triangles = [vertices]
    else:
        polygon = gpu.clip([gpu.transform(vertex) for vertex in vertices])
        points = [gpu.project(vertex) for vertex in polygon]
        triangles = [[points[0], points[i], points[i + 1]] for i in range(1, len(points) - 1)]
    result = {}
    for triangle in triangles:
        for x, y, depth, u, v, lod, colors in gpu.fragments(triangle):
            result[x, y] = (u / 256, v / 256, depth, max(0, min(8, lod / 256)), *colors)
    return result


class Metrics:
    def __init__(self):
        self.coverage = self.samples = self.mips = self.ideal_pixels = 0
        self.maximum = [0.] * 4
        self.squares = [0.] * 4
        self.count = [0] * 4

    def add(self, fixed, ideal):
        self.coverage += len(fixed.keys() ^ ideal.keys())
        self.ideal_pixels += len(ideal)
        for point in fixed.keys() & ideal.keys():
            a, b = fixed[point], ideal[point]
            self.samples += 1
            self.mips += math.floor(a[3]) != math.floor(b[3])
            errors = ([a[0] - b[0], a[1] - b[1]], [a[2] - b[2]], [a[3] - b[3]],
                      [a[i] - b[i] for i in (4, 5, 6)])
            for i, values in enumerate(errors):
                self.maximum[i] = max(self.maximum[i], *(abs(v) for v in values))
                self.squares[i] += sum(v * v for v in values)
                self.count[i] += len(values)

    def result(self):
        return dict(coverage_xor=self.coverage, samples=self.samples,
                    ideal_pixels=self.ideal_pixels, max=self.maximum,
                    rms=[math.sqrt(s / n) if n else 0 for s, n in zip(self.squares, self.count)],
                    mip_different_percent=100 * self.mips / self.samples)


class FilterMetrics:
    def __init__(self):
        self.maximum = self.squares = self.count = 0

    def add(self, a, b):
        for x, y in zip(a[:3], b[:3]):
            error = abs(x - y)
            self.maximum = max(self.maximum, error)
            self.squares += error * error
            self.count += 1

    def result(self):
        return [self.maximum, math.sqrt(self.squares / self.count)]


def texture_levels():
    # Nonconstant levels expose UV and fractional LOD differences in trilinear color.
    return [[((x * 31 // max(1, size - 1)) << 11)
             | ((y * 63 // max(1, size - 1)) << 5) | ((x + y + level * 5) & 31)
             for y in range(size) for x in range(size)]
            for level in range(9) for size in [256 >> level]]


def float_filter(fragment, levels):
    u, v, _, lod = fragment[:4]
    level = math.floor(lod)
    def bilinear(k):
        size = 256 >> k
        x, y = u / (1 << k) - .5, v / (1 << k) - .5
        ix, iy = math.floor(x), math.floor(y)
        fx, fy = x - ix, y - iy
        samples = [expand(levels[k][((iy + dy) % size) * size + (ix + dx) % size])
                   for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1))]
        weights = ((1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy)
        return [sum(c[channel] * w for c, w in zip(samples, weights)) for channel in range(3)]
    first = bilinear(level)
    if level == 8:
        return first
    second = bilinear(level + 1)
    return [a * (1 - (lod - level)) + b * (lod - level) for a, b in zip(first, second)]


def costs(plane_bits, mantissa_bits):
    def m(a, b):
        return ((a + 17) // 18) * ((b + 17) // 18)
    # 2 Newton + 2 UV + 8 derivative products per lane, sign outside unsigned DSPs.
    pixel_apm = 4 * 12 * m(mantissa_bits, mantissa_bits)
    # Two shared setup multiplier pools, reused for cross products and area NR.
    setup_apm = 2 * max(m(plane_bits + 24, 31), m(31, 32))
    # Explicit structural allowances; no soft multiplies or unrolled division.
    accumulator_bits = plane_bits + 38
    pixel_lut = (4 * 7 * accumulator_bits * 2 + 4 * 3 * accumulator_bits * 4
                 + 16 * (6 * mantissa_bits + 48) + 4 * 256 + 72 + 1000
                 + 4 * 1024 * max(0, mantissa_bits - 18) // 32)
    setup_lut = 2 * (plane_bits + 24 + 31) * 4 + 1200 + 384
    return dict(pixel_apm=pixel_apm, setup_apm=setup_apm,
                pixel_lut=pixel_lut, setup_lut=setup_lut,
                apm=pixel_apm + setup_apm, lut=pixel_lut + setup_lut,
                soft_multiplier_lut=0, unrolled_divider_lut=0)


def run():
    start = time.perf_counter()
    matrix = (255, 0, 0, 0, 0, 261, 0, 0, 0, 0, 128, -655, 0, 0, 256, 0)
    light = dict(LX=6000, LY=-4000, LZ=14700, AMB_RGB=0x202830, DIR_RGB=0xe0c090)
    engines = {'v0.2': ExactGPU(Memory(0, b''), reference_size=(640, 360))}
    widths = [(24, 16), (32, 18), (40, 22)]
    for b, p in widths:
        gpu = GPU(Memory(0, b''), reference_size=(640, 360))
        gpu._pixel_arithmetic = type('Candidate', (PixelArithmetic,),
                                    dict(PLANE_BITS=b, MANTISSA_BITS=p))
        engines[f'B{b}-P{p}'] = gpu
    for gpu in engines.values():
        gpu.matrix, gpu.light, gpu.pixel_state = matrix, light, {'CULL': 0}
        gpu.target = dict(TGT_X0=0, TGT_Y0=0, SC_X0=0, SC_Y0=0, SC_X1=640, SC_Y1=360,
                          VP_X0=0, VP_Y0=0, VP_W=640, VP_H=360)
    from tools.gpu.model.texture import Texture
    levels = texture_levels()
    for gpu in engines.values():
        gpu.ram[:] = interleave_texture(levels, 256, 256, 2)
        gpu.texture = Texture(gpu.ram, gpu.palettes,
                              dict(LOG2_W=8, LOG2_H=8, LEVELS=9, FORMAT=2,
                                   OFFSET=0, SAMPLE=2, PAL_GROUP=0, LOD_BIAS=0))
    totals = {name: Metrics() for name in engines}
    deltas = {name: Metrics() for name in engines if name != 'v0.2'}
    scenes = {name: {} for name in engines}
    filters = {name: FilterMetrics() for name in engines}
    filter_deltas = {name: FilterMetrics() for name in deltas}
    cases = [(name, vertices, False) for name, vertices in corpus()]
    cases += [(name, vertices, True) for name, vertices in screen_cases()]
    for scene, vertices, screen in cases:
        ideal = (ScreenIdeal if screen else Ideal)(matrix, light).fragments(vertices)
        exact = fixed_fragments(engines['v0.2'], vertices, screen)
        if screen:
            filtered_ideal = {point: float_filter(f, levels) for point, f in ideal.items()}
            filtered_exact = {point: engines['v0.2'].texture.sample(
                round(f[0] * 256), round(f[1] * 256), round(f[3] * 256))
                for point, f in exact.items()}
        for name, gpu in engines.items():
            fixed = exact if name == 'v0.2' else fixed_fragments(gpu, vertices, screen)
            totals[name].add(fixed, ideal)
            scenes[name].setdefault(scene, Metrics()).add(fixed, ideal)
            if name != 'v0.2':
                deltas[name].add(fixed, exact)
            if screen:
                for point in fixed.keys() & filtered_ideal.keys():
                    f = fixed[point]
                    sampled = gpu.texture.sample(round(f[0] * 256), round(f[1] * 256),
                                                 round(f[3] * 256))
                    filters[name].add(sampled, filtered_ideal[point])
                    if name != 'v0.2' and point in filtered_exact:
                        filter_deltas[name].add(sampled, filtered_exact[point])
    candidates = {}
    for name in engines:
        candidates[name] = dict(float=totals[name].result(),
                                scenes={s: m.result() for s, m in scenes[name].items()},
                                trilinear_color_max_rms=filters[name].result())
        if name != 'v0.2':
            candidates[name]['v02_delta'] = deltas[name].result()
            b, p = map(int, name.replace('B', '').replace('P', '').split('-'))
            candidates[name]['cost'] = costs(b, p)
            candidates[name]['trilinear_v02_max_rms'] = filter_deltas[name].result()
        print(name, json.dumps(candidates[name]), flush=True)
    return dict(seed=20261124, triangles=len(cases), viewport=[640, 360],
                metrics_order=['uv_texels', 'depth_u16', 'lod_levels', 'color_u8'],
                candidates=candidates, seconds=time.perf_counter() - start,
                max_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/gpu/study-v03.json'))
    args = parser.parse_args()
    result = run()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"study: {result['seconds']:.3f}s, RSS {result['max_rss_kib']} KiB")


if __name__ == '__main__':
    main()
