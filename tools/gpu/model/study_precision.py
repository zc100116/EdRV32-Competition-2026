#!/usr/bin/env python3
"""study_precision.py — gpu-spec 2.4/2.13 output precision experiment.
Standalone block-floating plane study and headless DDR replay; defaults unchanged.
Host standard library only, seed 20261124; no clock domain.
"""
import argparse
from array import array
import json
from pathlib import Path
import resource
import struct
import time
import zlib

from study_v03 import (GPU, Memory, Metrics, FilterMetrics, corpus, screen_cases,
                       fixed_fragments, texture_levels, interleave_texture)
from study_v03 import PixelArithmetic as HistoricalArithmetic
from tools.gpu.model.planes import PixelArithmetic
from tools.gpu.model.arithmetic import divide, edge, shift, saturate
from tools.gpu.model.texture import Texture

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'outputs/gpu-precision-20261127'
# Widths are Z/q/RGB, with P18 and the current quad LOD throughout.
CASES = {'P-A': ((32, 42, 32), 4, 0), 'P-A+': ((36, 46, 36), 4, 0),
         'P-B': ((28, 38, 28), 2, 0), 'P-C': ((28, 38, 28), 2, 8)}
FRAMES = ('canyon', 'world', 'world-dusk', 'rogue-slash')


class Narrow(PixelArithmetic):
    """Rebase existing rounded planes, then round to a bounded block exponent."""
    DOMAIN = (0, 0, 640, 360)
    LIMITS = (32, 42, 32)
    extra = [0] * 7

    def __init__(self, vertices, area):
        super().__init__(vertices, area)
        x, y, width, height = self.DOMAIN
        origin = (x // 4 * 4, y // 2 * 2)
        start = self.at(*origin)
        self.origin = origin
        # Includes the next four-lane step and both rows of helper pixels.
        guard = max(10, (width + height + 8).bit_length())
        span = 1 << guard
        limits = (self.LIMITS[0], *([self.LIMITS[1]] * 3), *([self.LIMITS[2]] * 3))
        coefficients = []
        for c, ((_, gx, gy), s, w) in enumerate(zip(self.coefficients, start, limits)):
            # Rounding contributes <= (1+span)/2; reserve it before choosing e.
            bound = abs(s) + span * max(abs(gx), abs(gy))
            allowance = (1 << (w-1)) - (span + 2)//2 - 1
            extra = (max(0, bound-1)//allowance).bit_length()
            coeff = tuple(shift(v, extra) for v in (s, gx, gy))
            self.extra[c] = max(self.extra[c], extra)
            self.exponents[c] += extra
            coefficients.append(coeff)
            # Experiment verification, not a production input check.
            assert abs(coeff[0]) + span * max(abs(coeff[1]), abs(coeff[2])) < 1 << (w-1)
        self.coefficients = coefficients


class CandidateGPU(GPU):
    guard = 4
    geometry_drop = 0

    def quantize(self, value, bits):
        size = bits-self.geometry_drop
        return saturate(shift(value, self.geometry_drop), -(1 << (size-1)),
                        (1 << (size-1))-1) << self.geometry_drop

    def transform(self, vertex):
        matrix = self.matrix
        self.matrix = tuple(self.quantize(v, 32) for v in matrix)
        result = super().transform(vertex)
        self.matrix = matrix
        result[:4] = [self.quantize(v, 40) for v in result[:4]]
        return result

    def clip(self, polygon):
        # Same symmetric intersection and plane order as the default model.
        planes = (lambda v: v[3] - 4096, lambda v: self.guard*v[3] + v[0],
                  lambda v: self.guard*v[3] - v[0], lambda v: self.guard*v[3] + v[1],
                  lambda v: self.guard*v[3] - v[1])
        for distance in planes:
            result = []
            if not polygon:
                break
            previous = polygon[-1]
            dp = distance(previous)
            for current in polygon:
                dc = distance(current)
                if (dp >= 0) != (dc >= 0):
                    point = [divide(a*dc-b*dp, dc-dp) for a, b in zip(previous, current)]
                    point[:4] = [self.quantize(v, 40) for v in point[:4]]
                    result.append(point)
                if dc >= 0:
                    result.append(current)
                previous, dp = current, dc
            polygon = result
        return polygon

    def fragments(self, vertices):
        x0, y0, x1, y1 = self.bounds()
        self._pixel_arithmetic.DOMAIN = (x0, y0, x1-x0, y1-y0)
        yield from super().fragments(vertices)


def engine(name, memory, size=None):
    gpu = (GPU if name in ('default', 'pc-v03') else CandidateGPU)(memory, reference_size=size)
    if name == 'pc-v03':
        gpu._pixel_arithmetic = HistoricalArithmetic
    elif name != 'default':
        widths, gpu.guard, gpu.geometry_drop = CASES[name]
        gpu._pixel_arithmetic = type('Plane', (Narrow,), dict(LIMITS=widths, extra=[0]*7))
    return gpu


def synthetic():
    matrix = (255, 0, 0, 0, 0, 261, 0, 0, 0, 0, 128, -655, 0, 0, 256, 0)
    light = dict(LX=6000, LY=-4000, LZ=14700, AMB_RGB=0x202830, DIR_RGB=0xe0c090)
    levels = texture_levels()
    engines = {n: engine(n, Memory(0, b''), (640, 360)) for n in ('default', *CASES)}
    for gpu in engines.values():
        gpu.matrix, gpu.light, gpu.pixel_state = matrix, light, {'CULL': 0}
        gpu.target = dict(TGT_X0=0, TGT_Y0=0, SC_X0=0, SC_Y0=0, SC_X1=640, SC_Y1=360,
                          VP_X0=0, VP_Y0=0, VP_W=640, VP_H=360)
        gpu.ram[:] = interleave_texture(levels, 256, 256, 2)
        gpu.texture = Texture(gpu.ram, gpu.palettes,
                              dict(LOG2_W=8, LOG2_H=8, LEVELS=9, FORMAT=2,
                                   OFFSET=0, SAMPLE=2, PAL_GROUP=0, LOD_BIAS=0))
    metrics = {n: Metrics() for n in CASES}
    filters = {n: FilterMetrics() for n in CASES}
    for _, vertices, screen in ([(n, v, False) for n, v in corpus()]
                                + [(n, v, True) for n, v in screen_cases()]):
        baseline = fixed_fragments(engines['default'], vertices, screen)
        for name in CASES:
            fixed = fixed_fragments(engines[name], vertices, screen)
            metrics[name].add(fixed, baseline)
            if screen:
                for point in fixed.keys() & baseline.keys():
                    samples = []
                    for fragments, gpu in ((fixed, engines[name]),
                                           (baseline, engines['default'])):
                        f = fragments[point]
                        samples.append(gpu.texture.sample(round(f[0]*256), round(f[1]*256),
                                                          round(f[3]*256)))
                    filters[name].add(*samples)
    return {n: dict(delta=metrics[n].result(), filtered=filters[n].result(),
                    extra=engines[n]._pixel_arithmetic.extra) for n in CASES}


class TrackedGPU:
    """Mixin records the primitive that most recently passed a pixel operation."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.primitive = 0
        self.owners = array('i', [-1]) * (self.width*self.height)
        self.resolves = []

    def draw_triangle(self, vertices):
        self.primitive += 1
        self.is_triangle = True
        super().draw_triangle(vertices)

    def quad(self, fields):
        self.primitive += 1
        self.is_triangle = False
        super().quad(fields)

    def pixel(self, x, y, *args, **kwargs):
        if self.is_triangle and not kwargs.get('transparent', False):
            self.attempts[x, y, self.primitive] = args[0]
        passed = self.regs['PERF[4]']
        super().pixel(x, y, *args, **kwargs)
        if self.regs['PERF[4]'] != passed and self.pixel_state['COLOR_WRITE']:
            self.owners[self.address(x, y)] = self.primitive

    def resolve(self, fields):
        self.resolves.append((dict(fields), self.target.copy(), self.width,
                              array('i', self.owners)))
        super().resolve(fields)

    def clear(self, fields):
        super().clear(fields)
        if fields['EN_COLOR']:
            x0, y0, x1, y1 = self.bounds()
            for y in range(y0, y1):
                for x in range(x0, x1):
                    self.owners[self.address(x, y)] = -1


def channels(value):
    return value >> 11, (value >> 5) & 63, value & 31


def depth_reason(depths):
    old_a, old_b, new_a, new_b = depths
    if new_a == new_b:
        return 'Quantization creates a depth tie; LEQUAL favors the later source.'
    if old_a == old_b:
        return 'Quantization separates an old depth tie; the nearer source now wins.'
    return 'Geometry/plane quantization reverses the depth difference.'


def png(path, width, height, rows):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack(
            '>I', zlib.crc32(kind + data))
    data = b''.join(b'\0' + row for row in rows)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack(
        '>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(data))
                     + chunk(b'IEND', b''))


def real_frame(frame):
    directory = ROOT / 'build/gpu/precision' / frame
    initial = (directory/'frame150-input.bin').read_bytes()
    expected = (directory/'frame150-output.bin').read_bytes()
    writes = [tuple(map(int, line.split())) for line in
              (directory/'frame150-writes.txt').read_text().splitlines()]
    results = {}
    baseline = None
    for name in ('pc-v03', 'default', *CASES):
        memory = Memory(0, initial)
        gpu = engine(name, memory)
        gpu.__class__ = type('Tracked', (TrackedGPU, type(gpu)), {})
        # Mixin state is initialized explicitly because engine already constructed the GPU.
        gpu.primitive = 0
        gpu.is_triangle = False
        gpu.attempts = {}
        gpu.owners = array('i', [-1]) * (gpu.width*gpu.height)
        gpu.resolves = []
        previous = (directory/'frame150-input.bin').read_bytes()
        submission = 0
        for offset, value in writes:
            if offset == 40:
                current = (directory/f'submit{submission:04d}-input.bin').read_bytes()
                for page in range(0, len(current), 4096):
                    if current[page:page+4096] != previous[page:page+4096]:
                        for i in range(page, min(page+4096, len(current))):
                            if current[i] != previous[i]:
                                memory.data[i] = current[i]
                gpu.write_register(offset, value)
                previous = (directory/f'submit{submission:04d}-output.bin').read_bytes()
                if name == 'pc-v03' and memory.data != previous:
                    first = next(i for i, (a, b) in enumerate(zip(memory.data, previous))
                                 if a != b)
                    raise AssertionError((frame, submission, hex(first),
                                          memory.data[first], previous[first]))
                submission += 1
            else:
                gpu.write_register(offset, value)
        if gpu.regs['ERR_CODE']:
            raise AssertionError((frame, name, gpu.regs['ERR_CODE']))
        # Compare all DDR bytes: includes texture/object state and every resolve.
        if name in ('pc-v03', 'default'):
            exact = memory.data == expected
            first = None
            if not exact:
                first = next(i for i, (a, b) in enumerate(zip(memory.data, expected)) if a != b)
            if name == 'pc-v03':
                assert exact, (frame, first)
            else:
                baseline = gpu
            results[name] = dict(ddr_bit_exact=exact, first_pc_difference=first,
                                 primitives=gpu.primitive, resolves=len(gpu.resolves))
            print(frame, name, results[name], flush=True)
            continue
        maximum = [0, 0, 0]
        different = pixels = 0
        changed_owners = []
        image = {}
        for (fields, target, width, owners), (_, _, _, oldowners) in zip(
                gpu.resolves, baseline.resolves):
            for y in range(fields['Y0'], fields['Y1']):
                for x in range(fields['X0'], fields['X1']):
                    addr = fields['BASE'] + y*fields['STRIDE'] + x*2
                    a = int.from_bytes(baseline.memory.read(addr, 2), 'little')
                    b = int.from_bytes(memory.read(addr, 2), 'little')
                    ac, bc = channels(a), channels(b)
                    delta = [abs(u-v) for u, v in zip(ac, bc)]
                    maximum = [max(u, v) for u, v in zip(maximum, delta)]
                    different += a != b
                    pixels += 1
                    index = (y-target['TGT_Y0'])*width+x-target['TGT_X0']
                    if owners[index] != oldowners[index]:
                        changed_owners.append([x, y, oldowners[index], owners[index]])
                    image[x, y] = (ac, bc, delta)
        xmax = max(p[0] for p in image)+1
        ymax = max(p[1] for p in image)+1
        flips = []
        for x, y, old, new in changed_owners:
            keys = ((x, y, old), (x, y, new))
            if all(k in baseline.attempts and k in gpu.attempts for k in keys):
                a, b = keys
                old_order = (baseline.attempts[b], -new) <= (baseline.attempts[a], -old)
                new_order = (gpu.attempts[b], -new) <= (gpu.attempts[a], -old)
                if old_order != new_order:
                    depths = [baseline.attempts[a], baseline.attempts[b],
                              gpu.attempts[a], gpu.attempts[b]]
                    flips.append([x, y, old, new, *depths, depth_reason(depths)])
        rows = []
        for y in range(ymax):
            row = bytearray()
            for panel in range(3):
                for x in range(xmax):
                    rgb = image.get((x, y), ((0, 0, 0),)*3)[panel]
                    for c, v in enumerate(rgb):
                        color = ((v << (3 if c != 1 else 2))
                                 | (v >> (2 if c != 1 else 4)))
                        row.append(color if panel < 2 else min(255, v*64))
            rows.append(bytes(row))
        png(OUT/frame/(name+'.png'), xmax*3, ymax, rows)
        results[name] = dict(max_rgb565=maximum, different_pixels=different, pixels=pixels,
                             different_percent=100*different/pixels,
                             owner_changes=changed_owners, depth_flips=flips,
                             extra=gpu._pixel_arithmetic.extra)
        print(frame, name, {k: (len(v) if k in ('owner_changes', 'depth_flips') else v)
                           for k, v in results[name].items()}, flush=True)
        del gpu
    return results


def resources():
    old = (62, 66, 66, 66, 58, 58, 58)
    def adder(w):
        return 3*w-min(35, w-1)+1
    result = {}
    for name, (limits, _, geometry_drop) in CASES.items():
        z, q, c = limits
        widths = (z, q, q, q, c, c, c)
        delta = sum(a-b for a, b in zip(old, widths))
        setup = sum(3*(a+2*(a-14))-3*(b+2*(b-10)) for a, b in zip(old, widths))
        raster = sum(22*(a-b)+8*((a-14)-(b-10))+6*(adder(a)-adder(b))
                     for a, b in zip(old, widths))
        perspective = 4*delta+12*(66-q)
        # Storage-only geometry subtotal; arithmetic recutting is not credited.
        geometry = dict(matrix_and_triangle=48*geometry_drop,
                        transform=14*geometry_drop, clip=20*geometry_drop,
                        project=3*geometry_drop)
        result[name] = dict(setup_ff_saved=setup, raster_ff_saved=raster,
                            perspective_ff_saved=perspective, geometry_ff_saved=geometry,
                            ff_saved_subtotal=setup+raster+perspective+sum(geometry.values()),
                            lut_saved_formula=8*delta+48*(66-q), apm_saved_credited=0)
    return result


def step_test():
    # Legal extreme s12.4 endpoints with area one exercise large setup cancellation.
    points = ((-65536, -65536), (65535, 65534), (65534, 65533))
    vertices = [[*p, z, q, 65535*q, 32768*q, *([color << 16]*3)]
                for p, z, q, color in zip(points, (0, 65535, 17),
                                          (1, 1 << 34, 1 << 20), (0, 255, 128))]
    area = edge(*vertices[:2], *vertices[2][:2])
    if area < 0:
        vertices[1], vertices[2] = vertices[2], vertices[1]
        area = -area
    for limits, _, _ in CASES.values():
        for domain in ((0, 0, 640, 180), (0, 180, 640, 180),
                       (-32768, -32768, 1280, 90), (0, 0, 640, 360), (17, 19, 1, 1)):
            cls = type('Step', (Narrow,), dict(DOMAIN=domain, LIMITS=limits, extra=[0]*7))
            plane = cls(vertices, area)
            x, y, width, height = domain
            widths = (limits[0], *([limits[1]]*3), *([limits[2]]*3))
            for yy in (y, y+height):
                values = plane.at(x, yy)
                for xx in range(x, x+width+4):
                    assert values == plane.at(xx, yy)
                    assert all(-(1 << (w-1)) <= v < 1 << (w-1)
                               for v, w in zip(values, widths))
                    values = [v+c[1] for v, c in zip(values, plane.coefficients)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--part', choices=('synthetic', *FRAMES), required=True)
    args = parser.parse_args()
    start = time.perf_counter()
    step_test()
    result = synthetic() if args.part == 'synthetic' else real_frame(args.part)
    result = dict(results=result, resources=resources(), step_test='PASS',
                  seconds=time.perf_counter()-start,
                  rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    destination = ROOT/'build/gpu/precision'/f'{args.part}.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result) if args.part == 'synthetic' else str(destination), flush=True)


if __name__ == '__main__':
    main()
