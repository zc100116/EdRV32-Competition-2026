#!/usr/bin/env python3
"""numeric.py — gpu-spec 9 G-N1–G-N3: deterministic fixed/float error experiment.
Host sequential study at 640x360, seed 20261124, standard library only.
Float geometry is independently evaluated; the integer path is the production model.
"""
from dataclasses import asdict, replace
import argparse
import json
import math
from pathlib import Path
import random
import resource
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.gpu.model import GPU, Numeric
from tools.gpu.model.arithmetic import expand
from tools.gpu.scene import Memory


class Ideal:
    """Unquantized transform, clipping, projection and rational attribute interpolation."""
    def __init__(self, matrix, light, numeric):
        self.matrix = [value / 65536 for value in matrix]
        self.light = light
        self.near = numeric.near_numerator / numeric.near_denominator
        self.guard = numeric.guard

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


def fixed_fragments(gpu, vertices):
    polygon = gpu.clip([gpu.transform(vertex) for vertex in vertices])
    screen = [gpu.project(vertex) for vertex in polygon]
    result = {}
    for index in range(1, len(screen) - 1):
        for x, y, depth, u, v, lod, colors in gpu.fragments(
                [screen[0], screen[index], screen[index + 1]]):
            result[(x, y)] = (u / 256, v / 256, depth,
                              max(0, min(8, lod / (1 << gpu.numeric.log_frac))), *colors)
    return result


class Metrics:
    def __init__(self):
        self.coverage = 0
        self.samples = 0
        self.ideal_pixels = 0
        self.maximum = [0.0] * 4
        self.squares = [0.0] * 4
        self.count = [0] * 4

    def add(self, fixed, ideal):
        self.coverage += len(fixed.keys() ^ ideal.keys())
        self.ideal_pixels += len(ideal)
        common = fixed.keys() & ideal.keys()
        self.samples += len(common)
        for point in common:
            a, b = fixed[point], ideal[point]
            errors = ([a[0] - b[0], a[1] - b[1]], [a[2] - b[2]],
                      [a[3] - b[3]], [a[index] - b[index] for index in (4, 5, 6)])
            for index, values in enumerate(errors):
                self.maximum[index] = max(self.maximum[index], *(abs(v) for v in values))
                self.squares[index] += sum(value * value for value in values)
                self.count[index] += len(values)

    def result(self):
        return dict(coverage_xor=self.coverage, common_samples=self.samples,
                    ideal_pixels=self.ideal_pixels, max=self.maximum,
                    rms=[math.sqrt(total / count) if count else 0
                         for total, count in zip(self.squares, self.count)])


def unit_sweep(numeric):
    reciprocal_relative = 0.0
    recovered_uv_error = 0.0
    for index in range(8193):
        # Sweep W from 1/256 to 8192, quantized only to the Q16 experiment input.
        value = round((2 ** (-8 + 21 * index / 8192)) * 65536)
        q = numeric.reciprocal(value, 16)
        exact = 65536 / value
        reciprocal_relative = max(reciprocal_relative,
                                  abs(q / (1 << numeric.reciprocal_frac) / exact - 1))
        inverse = numeric.reciprocal(q, numeric.reciprocal_frac)
        uv = (65535 * q * inverse) / (1 << (2 * numeric.reciprocal_frac)) / 256
        recovered_uv_error = max(recovered_uv_error, abs(uv - 65535 / 256))
    log_error = max(abs(numeric.logarithm(65536 + index, 16)
                        / (1 << numeric.log_frac) - math.log2(1 + index / 65536))
                    for index in range(65536))
    return dict(reciprocal_relative_max=reciprocal_relative,
                recovered_uv_texels_max=recovered_uv_error, log2_max=log_error)


def run():
    start = time.perf_counter()
    baseline = Numeric(clip_bits=40, clip_frac=16, log_table_bits=4)
    candidates = [
        ('N1-28-32', replace(baseline, matrix_frac=12, clip_bits=32, clip_frac=8)),
        ('N1-32-36', replace(baseline, clip_bits=36, clip_frac=12)),
        ('N1-32-40', replace(baseline, clip_bits=40, clip_frac=16)),
        ('N2-near256-G2', replace(baseline, near_denominator=256, guard=2)),
        ('N2-near16-G4', baseline),
        ('N2-near4-G8', replace(baseline, near_denominator=4, guard=8)),
        ('N3-8-0-L4', replace(baseline, reciprocal_table_bits=8, reciprocal_iterations=0)),
        ('N3-10-1-L4', baseline),
        ('N3-10-1-L8', replace(baseline, log_table_bits=8)),
    ]
    matrix = (255, 0, 0, 0, 0, 261, 0, 0, 0, 0, 128, -655, 0, 0, 256, 0)
    light = dict(LX=6000, LY=-4000, LZ=14700, AMB_RGB=0x202830, DIR_RGB=0xe0c090)
    cases = corpus()
    report = dict(seed=20261124, viewport=[0, 0, 640, 360], matrix=list(matrix),
                  light=light, triangles=len(cases), metrics_order=['uv_texels', 'depth_u16',
                                                                  'lod_levels', 'light_u8'],
                  candidates={})
    engines, totals, scenes = {}, {}, {}
    for name, numeric in candidates:
        gpu = GPU(Memory(0, b''), numeric, reference_size=(640, 360))
        gpu.target = dict(TGT_X0=0, TGT_Y0=0, SC_X0=0, SC_Y0=0, SC_X1=640, SC_Y1=360)
        gpu.matrix, gpu.light, gpu.pixel_state = matrix, light, {'CULL': 0}
        engines[name], totals[name], scenes[name] = gpu, Metrics(), {}
    # Keep at most one source triangle and its three ideal clipping variants in memory.
    for scene, vertices in cases:
        ideals = {}
        for name, numeric in candidates:
            key = (numeric.near_denominator, numeric.guard)
            if key not in ideals:
                ideals[key] = Ideal(matrix, light, numeric).fragments(vertices)
            ideal = ideals[key]
            fixed = fixed_fragments(engines[name], vertices)
            totals[name].add(fixed, ideal)
            if scene not in scenes[name]:
                scenes[name][scene] = Metrics()
            scenes[name][scene].add(fixed, ideal)
    for name, numeric in candidates:
        result = dict(parameters=asdict(numeric), total=totals[name].result(),
                      scenes={scene: metrics.result() for scene, metrics in scenes[name].items()})
        result['units'] = unit_sweep(numeric)
        report['candidates'][name] = result
        print(name, json.dumps(result['total']), flush=True)
    report['seconds'] = time.perf_counter() - start
    report['max_rss_kib'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/gpu/numeric.json'))
    args = parser.parse_args()
    report = run()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"numeric study: {report['seconds']:.3f} s; {args.output}")


if __name__ == '__main__':
    main()
