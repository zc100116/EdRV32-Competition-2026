#!/usr/bin/env python3
# File: geometry.py
# Spec: rnd 2.3/2.6; T-RNDMEAS.
# Description: Exact field and accumulator maxima over the host census.
# Clock domain: host.
import json
from pathlib import Path
import sys


def signed(value, bits=32):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def measure(path):
    maxima = {}
    counts = [0] * 16

    def observe(field, value, scene, op):
        value = abs(value)
        if field not in maxima or value > maxima[field]['absolute']:
            maxima[field] = dict(absolute=value, bits=value.bit_length() + 1,
                                 scene=scene, op=op)

    for row in path.read_text().splitlines():
        if not row.startswith('GEOMETRY,'):
            continue
        parts = row.split(',')
        scene, op, flags, x0, y0, x1, y1, cx0, cy0, cx1, cy1 = map(int, parts[1:12])
        p = [int(v, 16) for v in parts[12:]]
        counts[scene] += 1
        # Evaluate the actual RECT intersect CLIP, relative to the parameter origin.
        # E extrema are at corners; separable convex q has its minimum at the
        # nearest grid point to each parabola vertex, maximum at an endpoint.
        left, top = max(x0, cx0) - x0, max(y0, cy0) - y0
        right, bottom = min(x1, cx1) - x0, min(y1, cy1) - y0
        empty = right < left or bottom < top
        edges = (0, 3, 6) if op == 9 else (0, 3) if op == 10 else (16, 19)
        for k in edges:
            e0, ex, ey = [signed(v) for v in p[k:k + 3]]
            prefix = 'E' if op != 10 else ('T' if k == 0 else 'N')
            for suffix, value in zip(('0', 'x', 'y'), (e0, ex, ey)):
                observe(prefix + suffix, value, scene, op)
            if empty:
                continue
            for x in (left, right):
                for y in (top, bottom):
                    observe('E integer accumulated', e0 + x * ex + y * ey, scene, op)
            offsets = (1, 7) if flags & 1 else (4, 4)
            for a in (8 * left + offsets[0], 8 * right + offsets[1]):
                for b in (8 * top + offsets[0], 8 * bottom + offsets[1]):
                    observe('E sample x8', 8 * e0 + a * ex + b * ey, scene, op)
        if op == 10:
            for field, value in zip(('LENGTH', 'HALF_WIDTH'), p[6:8]):
                observe(field, value, scene, op)
        circles = () if op == 9 else (8, 12) if op == 10 else (0, 4, 8, 12)
        for k in circles:
            q0 = signed(p[k] | ((p[k + 1] & 65535) << 32), 48)
            dx, dy = signed(p[k + 2]), signed(p[k + 3])
            for field, value in zip(('q0', 'circle dx', 'circle dy'), (q0, dx, dy)):
                observe(field, value, scene, op)
            if empty:
                continue

            def candidates(step, start, stop, first, last, grid):
                vertex = -(step - 64) // 16
                lo, hi = 8 * start + first, 8 * stop + last
                left = (vertex - first) // grid * grid + first
                return {lo, hi, max(lo, min(hi, left)), max(lo, min(hi, left + grid))}

            for field, first, last, grid in (
                    ('q integer accumulated', 0, 0, 8),
                    ('q sample accumulated', 0 if flags & 1 else 3,
                     6 if flags & 1 else 3, 2 if flags & 1 else 8)):
                for a in candidates(dx, left, right, first, last, grid):
                    for b in candidates(dy, top, bottom, first, last, grid):
                        q = q0 + a * (dx - 64) // 8 + b * (dy - 64) // 8 + a*a + b*b
                        observe(field, q, scene, op)
    return dict(maxima=maxima, geometry_tasks=counts)


if __name__ == '__main__':
    print(json.dumps(measure(Path(sys.argv[1])), indent=2))
