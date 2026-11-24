# File: vectors.py
# Spec: gpu-spec 2.5, 2.8, 2.13.
# Description: Bit-packed unit stimuli and expected values using tools/gpu/model.
# Clock domain: none (host).
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu.model.arithmetic import edge, top_left, shift, saturate
from tools.gpu.model.planes import PixelArithmetic, pixel_seed
from tools.gpu.model.renderer import GPU
from types import SimpleNamespace

FRAG = dict(x=16, y=16, mask=4, quad=1, plane=1960, h=70, gradient=174, palette=4, alpha=8)
SAMPLE = dict(x=16, y=16, mask=4, quad=1, u=128, v=128, span=384,
              depth=64, color=96, palette=4, alpha=8)
SETUP = dict(bounds=64, edge=480, origin=32, start=490, gradient=784, h=70,
             normal_gradient=174)
QUAD = dict(data=128, x=17, y=17)


def packed(values, widths):
    result = 0
    offset = 0
    for value, width in zip(values, widths):
        result |= (value & ((1 << width)-1)) << offset
        offset += width
    return result


def record(fields, layout):
    return packed([fields[k] for k in layout], layout.values())


def norm(value):
    mantissa, exponent = value
    return packed([abs(mantissa), mantissa < 0, exponent], [18, 1, 10])


def normalized_gradients(arithmetic):
    return packed([norm(x) for axis in arithmetic.gradients for x in axis], [29]*6)


def limits(wide):
    return -5, -2, 1272 if wide else 632, 86 if wide else 176


def quad_case(x, y, w, h, flip_h, flip_v, wide, serial):
    # QUAD word layout comes from gpu.json; object uses the same non-position fields.
    data = packed([x, y, serial % 16, flip_h, flip_v, 0, w, h,
                   serial % 256, 0, serial % 256, (serial*7) % 256, serial % 65536],
                  [12, 12, 4, 1, 1, 2, 9, 9, 8, 6, 8, 8, 16])
    item = record(dict(data=data, x=x, y=y), QUAD)
    result = []
    cx0, cy0, cx1, cy1 = limits(wide)
    # Run the renderer's quad loop with a coordinate-recording texture probe.
    texel = []
    pixels = {}
    def sample(u, v, lod, palette, nearest):
        assert lod == 0 and nearest
        texel[:] = [u, v, palette]
        return 255, 255, 255, 255
    def pixel(px, py, depth, rgba, transparent):
        assert not transparent
        pixels[px, py] = (*texel, depth, rgba[3])
    gpu = GPU.__new__(GPU)
    gpu.bounds = lambda: limits(wide)
    gpu.perf = lambda counter: None
    gpu.texture = SimpleNamespace(sample=sample)
    gpu.pixel = pixel
    fields = dict(X=x, Y=y, W=w, H=h, U0=serial % 256, V0=(serial*7) % 256,
                  FLIP_H=flip_h, FLIP_V=flip_v, PAL_GROUP=serial % 16,
                  ALPHA=serial % 256, DEPTH=serial % 65536)
    gpu.quad(fields)
    object_pixels = pixels.copy()
    pixels.clear()
    gpu.object_quad(dict(fields, PX=(x+w//2)*256+127, PY=(y+h//2)*256+255))
    assert pixels == object_pixels
    for py in range(max(y, cy0), min(y+h, cy1)):
        for gx in range(max(x, cx0)//4*4, min(x+w, cx1), 4):
            mask = 0
            lanes = []
            for lane in range(4):
                px = gx+lane
                if (px, py) in pixels:
                    mask |= 1 << lane
                col, row = px-x, py-y
                if flip_h:
                    col = w-1-col
                if flip_v:
                    row = h-1-row
                u, v = serial % 256 + col, (serial*7) % 256 + row
                if (px, py) in pixels:
                    pu, pv, pal, z, alpha = pixels[px, py]
                    assert (u << 8, v << 8, serial % 16, serial % 65536,
                            serial % 256) == (pu, pv, pal, z, alpha)
                    u, v = pu >> 8, pv >> 8
                lanes.extend([serial % 65536 << 16, 1 << 30, u << 38, v << 38,
                              255 << 24, 255 << 24, 255 << 24])
            result.append(record(dict(x=gx, y=py, mask=mask, quad=1,
                                      plane=packed(lanes, [70]*28),
                                      h=packed([-16, 0, 0, 0, -8, -8, -8], [10]*7),
                                      gradient=0, palette=serial % 16,
                                      alpha=serial % 256), FRAG))
    return item, result


def quad_vectors(wide, obj, perf=False):
    inputs, outputs = [], []
    if perf:
        cases = [(32 if perf == 2 else 35, 2, 16, 16, 0, 0)]*32
    else:
        cases = [(12+align, 2, width, 3, fh, fv) for width in range(1, 65)
                 for align in range(4) for fh, fv in [(0, 0), (0, 1), (1, 0), (1, 1)]]
        cases += [(x, y, 17, 9, 1, 1) for x in [-20, -8, -5, 628, 632, 1270, 1400]
                  for y in [-15, -4, -2, 80, 85, 172, 175, 200]]
        cases += [(0, 0, 0, 9, 0, 0), (0, 0, 9, 0, 0, 0)]
        if obj:
            cases += [(x, y, 64, 8, 0, 1) for x, y in [(-32800, 0), (32735, 0),
                       (0, -32772), (0, 32763), (-2049, 4), (4096, 2)]]
    for serial, case in enumerate(cases):
        item, result = quad_case(*case, wide, serial)
        inputs.append(item)
        outputs.extend(result)
    return inputs, outputs


def vertices(points, seed):
    rng = random.Random(seed)
    result = []
    for x, y in points:
        q = rng.randrange(1 << 25, 1 << 35)
        result.append([x, y, rng.randrange(65536), q,
                       rng.randrange(-65536, 65536)*q, rng.randrange(-65536, 65536)*q,
                       *[rng.randrange(256) << 16 for _ in range(3)]])
    return result


def triangle_case(verts, wide):
    a, b, c = verts
    area = edge(a, b, c[0], c[1])
    if area == 0:
        # Setup discards degenerates; represent its empty traversal when directly testing raster.
        return record(dict(bounds=0, edge=0, origin=0, start=0, gradient=0, h=0,
                           normal_gradient=0), SETUP), [], None
    if area < 0:
        b, c = c, b
        area = -area
    ar = PixelArithmetic((a, b, c), area)
    x0 = (min(a[0], b[0], c[0])-8+15)//16//4*4
    y0 = (min(a[1], b[1], c[1])-8+15)//16
    x1 = (max(a[0], b[0], c[0])-8)//16+1
    y1 = (max(a[1], b[1], c[1])-8)//16+1
    cx0, cy0, cx1, cy1 = limits(wide)
    x0 = max(x0, cx0)//4*4
    y0 = max(y0, cy0)
    x1 = min(x1, cx1)
    y1 = min(y1, cy1)
    edges = ((b, c), (c, a), (a, b))
    edge_values = []
    for start, end in edges:
        edge_values.extend([edge(start, end, x0*16+8, y0*16+8),
                            (start[1]-end[1])*16, (end[0]-start[0])*16,
                            0 if top_left(start, end) else -1])
    item = record(dict(bounds=packed([x0, y0, x1, y1], [16]*4),
                       edge=packed(edge_values, [40]*12),
                       origin=packed(ar.origin, [16]*2),
                       start=packed([c[0] for c in ar.coefficients], [70]*7),
                       gradient=packed([v for coeff in ar.coefficients for v in coeff[1:]],
                                       [56]*14),
                       h=packed([e+f for e, f in zip(ar.exponents,
                                [0, 30, 38, 38, 16, 16, 16])], [10]*7),
                       normal_gradient=normalized_gradients(ar)), SETUP)
    cx0, cy0, cx1, cy1 = limits(wide)
    result = []
    for y in range(y0, y1):
        for x in range(x0, x1, 4):
            mask = 0
            for lane in range(4):
                px = x+lane
                weights = [edge(start, end, px*16+8, y*16+8) for start, end in edges]
                covered = all(w > 0 or (w == 0 and top_left(*e))
                              for w, e in zip(weights, edges))
                if covered and px < x1 and cx0 <= px < cx1 and cy0 <= y < cy1:
                    mask |= 1 << lane
            if mask:
                result.append(record(dict(x=x, y=y, mask=mask, quad=0,
                                          plane=packed([v for lane in range(4)
                                                        for v in ar.at(x+lane, y)], [70]*28),
                                          h=(item >> (64+480+32+490+784)) & ((1 << 70)-1),
                                          gradient=normalized_gradients(ar), palette=0,
                                          alpha=255), FRAG))
    return item, result, ar


def raster_vectors(wide):
    # Two pairs tile a rectangle, including centers lying exactly on a shared diagonal.
    cases = [[(8, 8), (328, 8), (328, 264)], [(8, 8), (328, 264), (8, 264)],
             [(-184, -88), (88, -88), (88, 104)], [(-184, -88), (88, 104), (-184, 104)],
             [(16, 16), (16, 16), (32, 32)], [(0, 0), (16, 16), (32, 32)],
             [(5, 6), (73, 17), (31, 147)], [(10040, 2650), (10280, 2650), (10040, 2890)],
             [(20240, 1270), (20450, 1270), (20330, 1510)],
             [(-32768, -32768), (32767, -32768), (10000, 32767)]]
    rng = random.Random(3947)
    cases += [[(rng.randrange(-192, 2400), rng.randrange(-64, 400)) for _ in range(3)]
              for _ in range(40)]
    inputs, outputs = [], []
    for i, points in enumerate(cases):
        item, result, _ = triangle_case(vertices(points, i), wide)
        inputs.append(item)
        outputs.extend(result)
    # The first two triangles cover exactly the 20x16 center grid once.
    first = []
    for i in range(2):
        _, groups, _ = triangle_case(vertices(cases[i], i), wide)
        for group in groups:
            x, y, mask = group & 65535, (group >> 16) & 65535, (group >> 32) & 15
            first.extend((x+lane, y) for lane in range(4) if mask >> lane & 1)
    assert len(first) == len(set(first)) == 320
    return inputs, outputs


def shade(ar, attrs):
    # Exercise the model's exact normal/multiply/subtract/inverse operations; keep span
    # before logarithm so this unit's Q16 boundary is checked directly.
    q, uq, vq = [ar.normal(attrs[c], ar.exponents[c]) for c in (1, 2, 3)]
    w = ar.inverse(q)
    uv = [ar.multiply(value, w) for value in (uq, vq)]
    span = 0
    for dq, duq, dvq in ar.gradients:
        for gradient, coordinate in zip((duq, dvq), uv):
            delta = ar.subtract(gradient, ar.multiply(coordinate, dq))
            value, exponent = ar.multiply(delta, w)
            span = max(span, shift(abs(value), -exponent-16))
    model = ar.shade(attrs)
    return model[0], model[1], model[2], span, model[4]


def perspective_vectors():
    inputs, outputs = [], []
    rng = random.Random(734199)
    for i in range(1800):
        ar = PixelArithmetic.__new__(PixelArithmetic)
        ar.exponents = [-16, rng.randrange(-65, -15), rng.randrange(-65, -15),
                        rng.randrange(-65, -15), -24, -24, -24]
        ar.gradients = [[ar.normal(rng.randrange(-(1 << 44), 1 << 44),
                                  ar.exponents[c]) for c in (1, 2, 3)] for _ in range(2)]
        if 1060 <= i < 1080:
            ar.exponents = [-16, -30, -38, -38, -24, -24, -24]
            ar.gradients = [[ar.normal(0), ar.normal(0), ar.normal(0)],
                            [ar.normal(1 << 30, -30), ar.normal(1 << 38, -38),
                             ar.normal(-(1 << 38), -38)]]
        lanes, zs, us, vs, spans, colors = [], [], [], [], [], []
        quad = i >= 1060 and i % 13 == 0
        for lane in range(4):
            # Include sign/tie/carry boundaries and large depth/color clamps.
            attrs = [rng.randrange(-(1 << 17), 1 << 34),
                     rng.randrange(1 << 40, 1 << 52),
                     rng.randrange(-(1 << 52), 1 << 52),
                     rng.randrange(-(1 << 52), 1 << 52),
                     *[rng.randrange(-(1 << 24), 1 << 34) for _ in range(3)]]
            if 1060 <= i < 1080:
                attrs[1:4] = [1 << 30, (0 if lane == 0 else 1 << 38),
                              0 if lane == 1 else -(1 << 38)]
            if i < 1024:
                attrs[1] = (131072 + i*128 + 64) << 20
            elif i < 1060:
                attrs[1] = (1 << 48) - 1
                attrs[2] = -((1 << 48) - 1)
                attrs[3] = (1 << 48) - 1
            if quad:
                attrs[1:4] = [1 << 30, rng.randrange(-100000, 100000) << 30,
                              rng.randrange(-100000, 100000) << 30]
                z = saturate(shift(attrs[0], 16), 0, 65535)
                u, v, span = attrs[2] >> 30, attrs[3] >> 30, 0
                color = [saturate(shift(a, 24), 0, 255) for a in attrs[4:]]
            else:
                z, u, v, span, color = shade(ar, attrs)
            lanes.extend(attrs)
            zs.append(z); us.append(u); vs.append(v); spans.append(span)
            colors.extend(color)
        x, y, mask = (i*4) % 1280, i % 90, rng.randrange(1, 16)
        palette, alpha = i % 16, i % 256
        h = packed([e+f for e, f in zip(ar.exponents, [0, 30, 38, 38, 16, 16, 16])], [10]*7)
        inputs.append(record(dict(x=x, y=y, mask=mask, quad=quad,
                                  plane=packed(lanes, [70]*28), h=h,
                                  gradient=normalized_gradients(ar), palette=palette,
                                  alpha=alpha), FRAG))
        outputs.append(record(dict(x=x, y=y, mask=mask, quad=quad,
                                   u=packed(us, [32]*4), v=packed(vs, [32]*4),
                                   span=packed(spans, [96]*4), depth=packed(zs, [16]*4),
                                   color=packed(colors, [8]*12), palette=palette,
                                   alpha=alpha), SAMPLE))
    # All seed values are generated from the same bit-accurate model primitive.
    assert all(pixel_seed(i, 18) == ((1 << 28)+(2049+2*i)//2)//(2049+2*i)
               for i in range(1024))
    return inputs, outputs


def run(kind):
    unit = ROOT / 'verif/unit' / ('gpu_'+kind)
    build = ROOT / 'build/unit' / ('gpu_'+kind)
    build.mkdir(parents=True, exist_ok=True)
    sources = ['-I'+str(ROOT/'rtl/include'), str(ROOT/f'rtl/gpu/edrv32_gpu_{kind}.v')]
    if kind == 'raster':
        sources.extend(str(p) for p in sorted((ROOT/'rtl/gpu').glob(
            'edrv32_gpu_raster_*.v')))
    if kind == 'perspective':
        sources.extend(str(p) for p in sorted((ROOT/'rtl/gpu').glob(
            'edrv32_gpu_perspective_*.v')))
        sources.append(str(ROOT/'rtl/tech/edrv32_rom_gpu_recip_p18.v'))
        sources.append(str(ROOT/'rtl/tech/edrv32_ram_gpu_delay.v'))
    subprocess.run(['iverilog', '-g2012', '-DSIM_MODE', '-s', 'tb', '-o', str(build/'sim'),
                    *sources, str(unit/'tb.sv')], check=True)
    if kind == 'perspective':
        cases = [(0, 0, stall, False) for stall in (0, 1)]
    elif kind == 'quad':
        cases = [(wide, obj, 1, False) for wide in (0, 1) for obj in (0, 1)]
        cases += [(wide, obj, 0, perf) for wide in (0, 1) for obj in (0, 1)
                  for perf in (1, 2)]
    else:
        cases = [(wide, 0, stall, False) for wide in (0, 1) for stall in (0, 1)]
    for wide, obj, stall, perf in cases:
        inputs, outputs = (perspective_vectors() if kind == 'perspective' else
                           quad_vectors(wide, obj, perf) if kind == 'quad' else
                           raster_vectors(wide))
        inp, out = build/'input.hex', build/'expected.hex'
        inp.write_text(''.join(f'{x:x}\n' for x in inputs))
        out.write_text(''.join(f'{x:x}\n' for x in outputs))
        print(f'{kind}: wide={wide} object={obj} stalls={stall} perf={perf}', flush=True)
        subprocess.run(['vvp', str(build/'sim'), f'+INPUT={inp}', f'+EXPECTED={out}',
                        f'+INPUT_COUNT={len(inputs)}', f'+OUTPUT_COUNT={len(outputs)}',
                        f'+WIDE={wide}', f'+OBJECT={obj}', f'+STALL={stall}',
                        f'+PERF={int(perf)}'], check=True)
