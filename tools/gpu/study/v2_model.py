#!/usr/bin/env python3
"""GPU v2 architecture study (2026-11-27 design record sections 3-4).
Host-only standard-library cost, workload and interpolation models; no clock domain.
Run from repository root; generated reports and the serial C emulator go under build/.
"""
import ctypes as C
import json
import math
from pathlib import Path
import random
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT), str(ROOT / 'tools/gpu/emu'),
                str(ROOT / 'tools/gpu/model'), str(ROOT / 'verif/block/gpu')]
from tools.gpu.scene import Scene, SCHEMA, unpack
from tools.gpu.model.planes import PixelArithmetic
from tools.gpu.model.arithmetic import edge
from study_v03 import screen_cases
import stress

OUT = ROOT / 'build/gpu/m4'
PDS_REF = '96fd08ecee9c771f840f1ccad75a62bcb55d54fc'
PDS_PATH = 'tasks/win/20261124-107-gpu-board/artifacts/round11/resource_hier.txt'
# All resource vectors: total LUT (including LUTRAM), FF, APM, DRM36K, LUTRAM.
# Columns are explicit design allocations, not a fitted synthesis prediction.
DEFAULT = {
    'command': (650, 700, 0, 0, 200),
    'geometry': (8500, 6200, 8, 3, 1400),
    'setup': (4300, 5400, 32, 2, 1100),
    'raster': (3300, 4300, 0, 0, 700),
    'perspective': (5500, 6000, 12, 1, 900),
    'texture': (7500, 6200, 76, 1, 1700),
    'pixel': (4400, 4600, 27, 0, 600),
    'target': (500, 650, 0, 5, 0),
    'resolve': (650, 650, 0, 0, 100),
    'object': (0, 0, 0, 0, 0), 'quad': (0, 0, 0, 0, 0),
    'regs': (1000, 1000, 0, 0, 150),
    'texture_ram': (600, 450, 0, 16, 0),
    'palette': (500, 400, 0, 0, 128),
    'read_dma': (1200, 1100, 0, 0, 300),
    'write_dma': (1600, 1000, 0, 0, 200),
    'unpack': (500, 900, 0, 0, 100),
    'list_pack': (0, 0, 0, 0, 0),
    'bridges': (391, 373, 0, 0, 309),
    'bin_cache': (1800, 1600, 0, 8, 500),
}
OPT_SAVINGS = {
    'command': (0, 512, 0, 0, -256),
    'geometry': (300, 2000, 0, 0, -512),
    'setup': (1800, 6000, 0, 0, -512),
    'raster': (300, 1500, 0, 0, -384),
    'perspective': (500, 1800, 0, 0, -512),
    'texture': (200, 1000, 0, 0, -256),
    'pixel': (100, 800, 0, 0, -256),
    'target': (0, 256, 0, 0, -128),
    'resolve': (0, 384, 0, 0, -128),
    'object': (0, 1024, 0, 0, -512),
    'quad': (0, 256, 0, 0, -128),
    'regs': (0, 688, 0, 0, -256),
    'unpack': (0, 768, 0, 0, -384),
    'list_pack': (0, 1024, 0, 0, -512),
}


def clm(v):
    return math.ceil(max(v[0] / 4, v[1] / 8) / .70)


def add(rows):
    return tuple(sum(v[i] for v in rows.values()) for i in range(5))


def pds():
    raw = subprocess.check_output(['git', 'show', f'{PDS_REF}:{PDS_PATH}'], text=True)
    rows = {}
    for line in raw.splitlines():
        match = re.fullmatch(r'\s*\d+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)'
                             r'\s+([\d.]+)( +)\+ u_(\w+)', line)
        if match:
            lut, ff, ram, apm, drm, indent, name = match.groups()
            if (len(indent) == 9 and 552 <= int(line.split()[0]) <= 2474
                    and name in DEFAULT):
                rows[name] = (int(lut), int(ff), int(apm), float(drm), int(ram))
            elif len(indent) == 5 and name == 'gpu':
                total = (int(lut), int(ff), int(apm), float(drm), int(ram))
    rows['bridges'] = (391, 373, 0, 0, 309)
    rows['other'] = tuple(total[i] - add(rows)[i] for i in range(5))
    return rows, total


def resource_model():
    current, total = pds()
    optimized = {k: tuple(v[i] - OPT_SAVINGS.get(k, (0,) * 5)[i] for i in range(5))
                 for k, v in current.items()}
    full = dict(DEFAULT)
    full.update(geometry=(14500, 10000, 12, 4, 2200),
                setup=(5200, 6500, 40, 2, 1400),
                raster=(4200, 5500, 0, 0, 1000),
                perspective=(8000, 8800, 24, 1, 1400),
                texture_ram=(850, 700, 0, 32, 0),
                target=(700, 900, 0, 8, 0),
                object=(1016, 4929, 0, 0, 24), quad=(963, 1921, 0, 0, 0),
                list_pack=(359, 2209, 0, 0, 0), resolve=(2026, 3289, 1, 3, 0))
    small = dict(DEFAULT)
    small.update(geometry=(5800, 4400, 6, 2, 1000),
                 setup=(3800, 4600, 24, 2, 900),
                 raster=(2600, 3500, 0, 0, 600),
                 perspective=(4300, 4800, 8, 1, 700),
                 texture=(6200, 5000, 52, 1, 1400),
                 texture_ram=(450, 350, 0, 8, 0),
                 target=(400, 500, 0, 2, 0))
    variants = dict(current=current, optimized=optimized, default=DEFAULT, full=full, small=small)
    return {k: dict(modules=v, module_clm={n: clm(r) for n, r in v.items()},
                    total=add(v), clm=clm(add(v)),
                    soc_clm=clm((add(v)[0] + 36282, add(v)[1] + 30818)))
            for k, v in variants.items()}


def workload():
    # stress uses Case()'s Scene; use a zero physical base for the public C API.
    original = Scene.__init__
    Scene.__init__ = lambda self, base=0: original(self, base)
    scene = stress.scene()
    Scene.__init__ = original
    writes = scene.finish()
    registers = {}
    for reg in SCHEMA['registers']:
        dims = reg['dimensions']
        for i in range(dims[0]['count'] if dims else 1):
            registers[reg['name'] + (f'[{i}]' if dims else '')] = (
                int(reg['offset'], 0) + (i * dims[0]['stride'] if dims else 0))
    libpath = OUT / 'libemu.so'
    subprocess.run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-DGPU_EMU_THREADS=1', '-shared', '-fPIC',
                    str(ROOT / 'tools/gpu/emu/gpu_emu.c'), '-o', str(libpath)], check=True)
    lib = C.CDLL(str(libpath))
    lib.gpu_emu_create.argtypes, lib.gpu_emu_create.restype = [C.c_void_p, C.c_uint32], C.c_void_p
    lib.gpu_emu_write.argtypes = [C.c_void_p, C.c_uint32, C.c_uint32]
    lib.gpu_emu_read.argtypes, lib.gpu_emu_read.restype = [C.c_void_p, C.c_uint32], C.c_uint32
    lib.gpu_emu_destroy.argtypes = [C.c_void_p]
    memory = C.create_string_buffer(bytes(scene.memory.data))
    emu = lib.gpu_emu_create(memory, len(memory))
    for name, value in writes:
        lib.gpu_emu_write(emu, registers[name], value)
    perf = [lib.gpu_emu_read(emu, registers[f'PERF[{i}]']) for i in range(9)]
    error = lib.gpu_emu_read(emu, registers['ERR_CODE'])
    lib.gpu_emu_destroy(emu)
    assert error == 0, error
    triangles = quads = texture_bytes = tex_switches = 0
    tile_refs = stripe_refs = 0
    for command in scene.commands:
        if command[0] == 0x20:
            draw = unpack('CMD_DRAW_TRI', command)
            triangles += draw['COUNT']
            for i in range(draw['COUNT']):
                points = [unpack('VERTEX', scene.memory.read(draw['ADDR'] + (3*i+j)*16, 16))
                          for j in range(3)]
                xs, ys = [p['X'] for p in points], [p['Y'] for p in points]
                # Source triangles in this fixture use exact integer screen positions.
                tile_refs += ((max(xs)-1)//64-min(xs)//64+1) * (
                    (max(ys)-1)//64-min(ys)//64+1)
                stripe_refs += (max(ys)-1)//180-min(ys)//180+1
        elif command[0] == 0x21:
            quads += unpack('CMD_DRAW_QUAD', command)['COUNT']
        elif command[0] == 0x30:
            texture_bytes += unpack('CMD_TEX_LOAD', command)['BYTES']
        elif command[0] == 3:
            tex_switches += 1
    return dict(perf=perf, triangles=triangles, quads=quads, texture_upload_bytes=texture_bytes,
                texture_state_commands=tex_switches, triangle_tile_refs=tile_refs,
                triangle_stripe_refs=stripe_refs, command_bytes=len(scene.commands)*32,
                source_vertex_bytes=triangles*3*16,
                passed_overdraw=perf[4]/(640*360))


def vertex_cycles(width, lights, generic=False):
    # Four component vector schedule: base + per-light instructions including RAW slots.
    return (4/width) * ((288 + 176*lights) if generic else (64 + 32*lights))


def performance(w):
    result = []
    for lights in (1, 8):
        for generic in (False, True):
            for name, width in (('small', 1), ('default', 2), ('full', 4)):
                cycles = vertex_cycles(width, lights, generic)
                # Lower bounds for overlapped engines; serial upper planning budget below.
                geom = w['triangles']*3*cycles
                fragments = w['perf'][4]
                rate = .5 if name == 'small' else 1
                pixels = fragments/rate  # two bilinear textures
                setup = w['triangle_tile_refs']*16
                bus_bytes = (w['triangles']*3*(64+2*80) + w['triangle_tile_refs']*8*2
                             + 640*360*2 + fragments*16*.10)
                ddr_cycles = bus_bytes / (8*.55)  # 64-bit, 55% sustained
                ui_vertices = w['quads']*4
                ui_extra = (ui_vertices*(32 if name == 'small' else 16)
                            + w['quads']*2*16 + ui_vertices*(64+2*80)/(8*.55)
                            if name != 'full' else 0)
                result.append(dict(config=name, lights=lights, generic=generic,
                                   vertex_cycles=cycles, geometry_cycles=geom,
                                   texture_cycles=pixels, setup_cycles=setup,
                                   ddr_bytes=bus_bytes, ui_expansion_cycles=ui_extra,
                                   with_ui_ms_150=(geom+pixels+setup+ddr_cycles
                                                   +115200+ui_extra)/150000,
                                   with_ui_ms_200=(geom+pixels+setup+ddr_cycles
                                                   +115200+ui_extra)/200000,
                                   lower_ms_150=max(geom, pixels, setup, ddr_cycles)/150000,
                                   serial_ms_150=(geom+pixels+setup+ddr_cycles+115200)/150000,
                                   serial_ms_200=(geom+pixels+setup+ddr_cycles+115200)/200000))
    return result


def rounded(value, bits):
    if value == 0:
        return 0.
    _, exponent = math.frexp(value)
    return math.ldexp(round(math.ldexp(value, bits-exponent)), exponent-bits)


def interpolation():
    # Exercise actual P-A q/uq/vq for two texture projective denominators.
    # Barycentric candidate: Q24 lambdas, 24-significant-bit multiply/add.
    # Block setup candidate: shared exponent, 24-bit signed S/gx/gy per attribute.
    rng = random.Random(20261127)
    cases = list(screen_cases())
    for index in range(48):
        x, y = rng.randrange(0, 560), rng.randrange(0, 280)
        points = [(x, y), (x+rng.randrange(1, 80), y+1), (x+1, y+rng.randrange(2, 80))]
        vertices = []
        for xx, yy in points:
            q = round(2**30 / 2**rng.uniform(-4, 4))
            vertices.append([16*xx, 16*yy, rng.randrange(65536), q,
                             rng.randrange(65536)*q, rng.randrange(65536)*q,
                             *[rng.randrange(256)*65536 for _ in range(3)]])
        cases.append((f'random-{index}', vertices))
    metrics = {name: dict(samples=0, max_uv=0., square_uv=0., max_z=0.,
                         square_z=0., max_color=0., square_color=0.,
                         mip_different=0, max_lod=0.)
               for name in ('P-A', 'bary24', 'block24')}
    denominator_min = math.inf
    for _, original in cases:
        for unit in (0, 1):
            vertices = [v.copy() for v in original]
            if unit == 1:
                # Projective texture q is independently nonunit at each vertex.
                for i, v in enumerate(vertices):
                    v[3] *= (1, 2, 4)[i]
                    v[4], v[5] = v[5], -v[4]
            a, b, c = vertices
            area = edge(a, b, c[0], c[1])
            if area < 0:
                b, c, area = c, b, -area
            vertices = [a, b, c]
            plane = PixelArithmetic(vertices, area)
            edges = ((b, c), (c, a), (a, b))
            dx = [(p[1]-q[1])*16/area for p, q in edges]
            dy = [(q[0]-p[0])*16/area for p, q in edges]
            # Double coefficients, then one common exponent per attribute's S/gx/gy.
            coeff = []
            for channel in range(2, 9):
                gx = sum(d*v[channel] for d, v in zip(dx, vertices))
                gy = sum(d*v[channel] for d, v in zip(dy, vertices))
                ox, oy = (min(v[0] for v in vertices)//16, min(v[1] for v in vertices)//16)
                start = a[channel] + ((ox+.5)-a[0]/16)*gx + ((oy+.5)-a[1]/16)*gy
                exponent = math.frexp(max(abs(start), abs(gx), abs(gy)))[1]-23
                coeff.append(([round(math.ldexp(v, -exponent)) for v in (start, gx, gy)],
                              exponent))
            for y in range(min(v[1] for v in vertices)//16,
                           max(v[1] for v in vertices)//16, 3):
                for x in range(min(v[0] for v in vertices)//16,
                               max(v[0] for v in vertices)//16, 3):
                    weights = [edge(p, q, x*16+8, y*16+8)/area for p, q in edges]
                    if min(weights) <= 0:
                        continue
                    exact = [sum(w*v[k] for w, v in zip(weights, vertices)) for k in range(2, 9)]
                    denominator_min = min(denominator_min, exact[1])
                    reference = [exact[2]/exact[1]/256, exact[3]/exact[1]/256,
                                 exact[0], *[v/65536 for v in exact[4:]]]
                    pa = plane.shade(plane.at(x, y))
                    values = {'P-A': [pa[1]/256, pa[2]/256, pa[0], *pa[4]]}
                    lambdas = [round(w*2**24)/2**24 for w in weights[:2]]
                    lambdas.append(1-sum(lambdas))
                    attrs = [rounded(sum(rounded(w*v[k], 24)
                                         for w, v in zip(lambdas, vertices)), 24)
                             for k in range(2, 9)]
                    block = [math.ldexp(s+(x-ox)*gx+(y-oy)*gy, e)
                             for (s, gx, gy), e in coeff]
                    for name, data in (('bary24', attrs), ('block24', block)):
                        values[name] = [data[2]/data[1]/256, data[3]/data[1]/256,
                                        data[0], *[v/65536 for v in data[4:]]]
                    for name, value in values.items():
                        m = metrics[name]
                        m['samples'] += 1
                        for key, indices in (('uv', (0, 1)), ('z', (2,)),
                                             ('color', (3, 4, 5))):
                            errors = [value[i]-reference[i] for i in indices]
                            m['max_'+key] = max(m['max_'+key], *map(abs, errors))
                            m['square_'+key] += sum(e*e for e in errors)
    for m in metrics.values():
        for key, count in (('uv', 2), ('z', 1), ('color', 3)):
            m['rms_'+key] = math.sqrt(m.pop('square_'+key)/(m['samples']*count))
        # LOD/filter errors require helper-pixel sampling, not covered-point samples.
        del m['mip_different'], m['max_lod']
    return dict(seed=20261127, source_triangles=len(cases), texture_sets=2,
                coverage_xor=0, coverage_reason='shared exact edge predicate; no geometry changes',
                minimum_interpolated_denominator=denominator_min, metrics=metrics,
                scope='sampled screen interpolation only; no ES conformance or new geometry proof')


def vertex_comparison():
    resources = {
        'fixed_extended': (18000, 26000, 104, 3, 3000),
        'fp32_4': (14500, 10000, 12, 4, 2200),
        'fp32_2': DEFAULT['geometry'],
        'fp32_1': (5800, 4400, 6, 2, 1000),
        'cpu_F_gpu_frontend': (4300, 4700, 12, 1, 900),
    }
    old = (9127, 20568, 64, 1, 1918)
    rows = {}
    for name, value in resources.items():
        cycles = {}
        for lights in (1, 8):
            if name == 'fixed_extended':
                direct, generic = 32+16*lights, 80+112*lights
            elif name == 'cpu_F_gpu_frontend':
                direct, generic = 960+384*lights, 2240+1856*lights
            else:
                width = int(name[-1])
                direct = vertex_cycles(width, lights)
                generic = vertex_cycles(width, lights, True)
            cycles[str(lights)] = dict(direct=direct, generic=generic,
                                      direct_Mvertices_150=150/direct,
                                      direct_Mvertices_200=200/direct)
        rows[name] = dict(resources=value, clm=clm(value),
                          delta_geometry=[a-b for a, b in zip(value, old)], cycles=cycles)
    return rows


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    resources = resource_model()
    measured = workload()
    result = dict(source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                       text=True).strip(),
                  pds_ref=subprocess.check_output(['git', 'rev-parse', PDS_REF],
                                                  text=True).strip(),
                  resources=resources, vertex_comparison=vertex_comparison(),
                  measured_workload=measured,
                  performance_estimates=performance(measured), interpolation=interpolation())
    (OUT / 'v2-model.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
