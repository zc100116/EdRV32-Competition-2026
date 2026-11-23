#!/usr/bin/env python3
# File: run.py
# Spec: gpu-spec 2.13.1-6 and 7; R-2 unit verification.
# Description: Generate independent model vectors, build, and run the setup scoreboard.
# Clock domain: host tool.
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu.model.arithmetic import edge, top_left
from tools.gpu.model.planes import PixelArithmetic


def pack(values, width):
    return sum((v & ((1 << width) - 1)) << (i * width) for i, v in enumerate(values))


def vectors():
    rng = random.Random(0x5232)
    incoming, expected = [], []
    for index in range(264):
        points = [(rng.randrange(-65536, 65536), rng.randrange(-65536, 65536))
                  for _ in range(3)]
        if index == 260:
            points = [(0, 0), (0, 0), (0, 0)]
        if index == 261:
            points = [(16, 16), (32, 32), (48, 48)]
        if index == 262:
            points = [(1, 1), (2, 1), (1, 2)]
        if index == 263:
            points = [(-16, -16), (0, -16), (-16, 0)]
        vertices = [list(p) + [rng.randrange(65536), rng.randrange(1, (16 << 30) + 1),
                              rng.randrange(1 << 50), rng.randrange(1 << 50)]
                    + [rng.randrange(1 << 24) for _ in range(3)] for p in points]
        if index in (262, 263):
            for v in vertices:
                v[3:6] = [0, 0, 0]
        area = edge(vertices[0], vertices[1], *vertices[2][:2])
        if area < 0:
            vertices[1], vertices[2] = vertices[2], vertices[1]
            area = -area
        fields = [(pack([v[c] for v in vertices], w), 3*w)
                  for c, w in enumerate((17, 17, 16, 35, 51, 51))]
        fields += [(pack([v[c] for v in vertices for c in (6, 7, 8)], 24), 216)]
        value, offset = 0, 0
        for field, width in fields:
            value |= field << offset
            offset += width
        incoming.append(f'{value:0195x}\n')
        if area == 0:
            continue
        arithmetic = PixelArithmetic(vertices, area)
        xr, yr = arithmetic.origin
        x0 = ((min(v[0] for v in vertices) + 7) // 16 // 4) * 4
        y0 = (min(v[1] for v in vertices) + 7) // 16
        x1 = (max(v[0] for v in vertices) - 8) // 16 + 1
        y1 = (max(v[1] for v in vertices) - 8) // 16 + 1
        a, b, c = vertices
        edges = []
        for start, end in ((b,c), (c,a), (a,b)):
            edges += [edge(start, end, 16*x0+8, 16*y0+8),
                      (start[1]-end[1])*16, (end[0]-start[0])*16,
                      0 if top_left(start, end) else -1]
        normals = []
        for axis in range(2):
            for mantissa, exponent in arithmetic.gradients[axis]:
                normals.append((abs(mantissa) | (int(mantissa < 0) << 18)
                                | ((exponent & 1023) << 19)))
        fields = [(pack([x0,y0,x1,y1],16),64), (pack(edges,40),480),
                  (pack([xr,yr],16),32),
                  (pack([c[0] for c in arithmetic.coefficients],70),490),
                  (pack([v for c in arithmetic.coefficients for v in c[1:]],56),784),
                  (pack([e+f for e,f in zip(arithmetic.exponents,(0,30,38,38,16,16,16))],10),70),
                  (pack(normals,29),174)]
        value, offset = 0, 0
        for field, width in fields:
            value |= field << offset
            offset += width
        expected.append(f'{value:0524x}\n')
    out = ROOT / 'build/gpu_setup'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'input.hex').write_text(''.join(incoming))
    (out / 'expected.hex').write_text(''.join(expected))


def main():
    vectors()
    out = ROOT / 'build/gpu_setup'
    subprocess.run(['verilator', '-DSIM_MODE', '--binary', '--timing', '-j', '1',
                    '--top-module', 'tb_gpu_setup', '--Mdir', str(out / 'obj'),
                    '-o', 'sim', '-f', 'files.f'], cwd=Path(__file__).resolve().parent, check=True)
    subprocess.run([str(out / 'obj/sim')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
