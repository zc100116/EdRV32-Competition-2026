#!/usr/bin/env python3
"""M-7 GPU resource/width/frame planning estimates, design record section 9.
Standard-library host model; no RTL clock domain or synthesis measurements.
Run at repository root; generated tables and JSON go under build/gpu/m7.
"""
from collections import Counter
import heapq
import json
import math
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from m6_model import resources
from m5_setup import dag

OUT = Path(__file__).resolve().parents[3] / 'build/gpu/m7'
# Explicit M-6 section 8.7 inputs, not a new emulator measurement.
T, V, REFS, FRAG, QUADS = 1000, 3000, 1634, 717910, 2000
CYCLES = dict(small=(153.75, 265.75, 358.50, 1536.25),
              default=(92.25, 161.25, 262., 1229.75),
              full=(66., 109.75, 220., 1119.50))
# (module, variable LUT/FF/LR at W256, length in relative placement units).
# Variable portions are explicit assumptions; the remaining M-6 allocation is fixed.
PATHS = [('read_dma', 800, 800, 256, 4),
         ('write_dma', 1100, 800, 128, 4),
         ('unpack', 320, 768, 64, 2),
         ('bridges', 291, 256, 256, 8),
         ('texture', 256, 512, 0, 3),
         ('bin_cache', 256, 512, 128, 3),
         ('resolve', 128, 256, 64, 2)]


def total(rows):
    return [sum(row[i] for row in rows.values()) for i in range(5)]


def clm(row):
    return math.ceil(max(row[0]/4, row[1]/8)/.70)


def retimed_setup(attrs, extra, count=512):
    """M-6 scheduler with one explicit synchronous fetch cycle per arithmetic op.
    Keeps M-6 field-bank independence assumption; does not prove bank assignment.
    Arithmetic II/ports unchanged: fetch is a preceding pipelined stage.
    """
    nodes = dag(attrs)
    index = {node[0]: i for i, node in enumerate(nodes)}
    children = [[] for _ in nodes]
    for i, node in enumerate(nodes):
        for dep in node[2]:
            children[index[dep]].append(i)
    latency = dict(mul=6+extra, add=2+extra, norm=2+extra, read=1+extra, write=1)
    ports = dict(mul=4, add=2, norm=2, read=1, write=1)
    critical = [0]*len(nodes)
    for i in range(len(nodes)-1, -1, -1):
        critical[i] = latency[nodes[i][1]] + max(
            (critical[j] for j in children[i]), default=0)
    queues = {kind: [] for kind in ports}
    pending, remaining, retired, events, finishes = {}, {}, {}, [], []
    head = next_triangle = cycle = 0
    while head < count:
        while events and events[0][0] <= cycle:
            _, triangle, i = heapq.heappop(events)
            remaining[triangle] -= 1
            for j in children[i]:
                pending[triangle][j] -= 1
                if not pending[triangle][j]:
                    heapq.heappush(queues[nodes[j][1]], (triangle, -critical[j], j))
            if not remaining[triangle]:
                retired[triangle] = cycle
        while head in retired:
            finishes.append(cycle)
            del pending[head], remaining[head], retired[head]
            head += 1
        while next_triangle < min(count, head+4):
            triangle = next_triangle
            pending[triangle] = [len(node[2]) for node in nodes]
            remaining[triangle] = len(nodes)
            for i, node in enumerate(nodes):
                if not node[2]:
                    heapq.heappush(queues[node[1]], (triangle, -critical[i], i))
            next_triangle += 1
        for kind, capacity in ports.items():
            for _ in range(min(capacity, len(queues[kind]))):
                triangle, _, i = heapq.heappop(queues[kind])
                heapq.heappush(events, (cycle+latency[kind], triangle, i))
        cycle += 1
    middle = finishes[count//4:3*count//4]
    gaps = [b-a for a, b in zip(middle, middle[1:])]
    return dict(first=finishes[0], mean=sum(gaps)/len(gaps), minimum=min(gaps),
                maximum=max(gaps), count=count, work=dict(Counter(n[1] for n in nodes)))


def width_model(width):
    ratio = width/256
    # One read and one write converter at the xbar boundary; extra narrow control.
    converter = (0, 0) if width == 256 else (384, 768)
    savings = [math.floor(sum(p[i] for p in PATHS)*(1-ratio)) for i in (1, 2, 3)]
    wire = sum(width*p[4] for p in PATHS) + (0 if width == 256 else 2*256)
    return dict(width=width, gross_saving=savings, converter_lut_ff=converter,
                net_saving=[savings[0]-converter[0], savings[1]-converter[1], savings[2]],
                wire_bit_length=wire, wire_ratio=wire/(256*sum(p[4] for p in PATHS)),
                raw_MBps_180=width/8*180, effective_MBps_180=width/8*180*.55)


def resource_model(width, rf=False):
    rows = {name: list(row) for name, row in resources()['default']['modules'].items()}
    # Setup: 3 shared input banks x64x58, 32 scratch banks x16x92.
    # 1R1W SDP72: 3 + 32*ceil(92/72) DRM. Input context address is concatenated.
    # Charge full output captures externally, even if later absorbed into DRM registers.
    setup_delta = [-3640+128, 3*58+32*92+128, 0, 3+32*math.ceil(92/72), -3640]
    sfu_delta = [-512+256, 16*32+64, 0, 16, -512]
    for module, delta in [('setup', setup_delta), ('geometry', sfu_delta)]:
        rows[module] = [a+b for a, b in zip(rows[module], delta)]
    if rf:
        # Optional 3R1W RF: three 128x128 SDP copies, write broadcast.
        # 3*128-bit bypass mux +64 address/control LUT; +448 external FF.
        delta = [-768+384+64, 448, 0, 3*math.ceil(128/72), -768]
        rows['geometry'] = [a+b for a, b in zip(rows['geometry'], delta)]
    ratio = width/256
    for name, lut, ff, lr, _ in PATHS:
        for i, variable in ((0, lut), (1, ff), (4, lr)):
            rows[name][i] -= math.floor(variable*(1-ratio))
    if width != 256:
        rows['bridges'][0] += 384
        rows['bridges'][1] += 768
    # Two frame descriptors, separate ready/retired state, epoch/arbiter bookkeeping.
    # One 128x64 draw-state descriptor bank; pixel state snapshots stay in DDR.
    rows['frame_overlap'] = [200, 512, 0, 1, 0]
    result = total(rows)
    return dict(modules=rows, total=result, gpu_clm=clm(result),
                soc_clm=clm((result[0]+36282, result[1]+30818)),
                clms_min=math.ceil(result[4]/4),
                clms_plan=math.ceil(result[4]/(4*.70)),
                soc_drm=result[3]+58.5,
                soc_clms_min=math.ceil((result[4]+1241)/4),
                soc_clms_plan=math.ceil((result[4]+1241)/(4*.70)))


def frames(setup):
    rows = []
    first, service = setup['first'], math.ceil(setup['mean'])
    for config, cycles in CYCLES.items():
        for load, vertex in zip(('D1', 'D8', 'G1', 'G8'), cycles):
            for ui in (False, True):
                sources, refs, vertices = T, REFS, V
                geometry = vertices*vertex + first+(sources-1)*service+refs*11+3
                if ui and config != 'full':
                    sources += 2*QUADS
                    refs += 2*QUADS
                    vertices += 4*QUADS
                    geometry += (4*QUADS*(32 if config == 'small' else 16)
                                 + first+(2*QUADS-1)*service+2*QUADS*11+3)
                pixel = FRAG/(.5 if config == 'small' else 1)+115200
                for miss in (.1, .5):
                    data = (vertices*(64+2*80)+refs*16+640*360*2+FRAG*16*miss
                            +(sources+refs)*288)
                    ddr = data/(8*.55)
                    serial = geometry+pixel+ddr
                    lower = max(geometry, pixel, ddr)
                    # Only cross-frame compute overlap credited; all DDR time charged in full.
                    planning = max(geometry, pixel)+ddr
                    rows.append(dict(config=config, load=load, ui=ui, miss=miss,
                                     geometry_cycles=geometry, pixel_cycles=pixel,
                                     ddr_bytes=data, ddr_cycles=ddr,
                                     serial_ms=[serial/f for f in (150000, 200000)],
                                     overlap_ms=[planning/f for f in (150000, 200000)],
                                     lower_ms=[lower/f for f in (150000, 200000)],
                                     required_MBps_180=data/(planning/180),
                                     required_MBps_60Hz=data*60/1e6))
    return rows


def slot_capacity(ui):
    sources, refs, vertices = T, REFS, V
    if ui:
        sources += QUADS*2
        refs += QUADS*2
        vertices += QUADS*4
    raw = refs*16+60*8+(sources+refs)*288+vertices*80
    aligned = math.ceil(raw/4096)*4096
    return dict(raw_bytes=raw, aligned_bytes=aligned, double_bytes=aligned*2)


def tables(result):
    lines = ['| module | M-6 performance | M-7 W64 | M-7 W128 + RF |',
             '|---|---|---|---|']
    baseline = resources()['default']['modules']
    for name, row in result['resources']['64']['modules'].items():
        values = [baseline.get(name, (0,)*5), row,
                  result['resources']['128_rf']['modules'][name]]
        lines.append('| '+name+' | '+' | '.join('/'.join(map(str, v)) for v in values)+' |')
    for key in ('total', 'gpu_clm', 'soc_clm', 'clms_min', 'clms_plan', 'soc_drm'):
        lines.append('| '+key+' | — | '+' | '.join(str(result['resources'][c][key])
                                                   for c in ('64', '128_rf'))+' |')
    lines += ['', '| config/load | serial 150/200 | overlap 150/200 | '
              'UI overlap 150/200 | miss50 overlap 150/200 |', '|---|---:|---:|---:|---:|']
    for config in CYCLES:
        for load in ('D1', 'D8', 'G1', 'G8'):
            matches = [r for r in result['frames'] if r['config'] == config and r['load'] == load]
            base = next(r for r in matches if not r['ui'] and r['miss'] == .1)
            ui = next(r for r in matches if r['ui'] and r['miss'] == .1)
            miss = next(r for r in matches if not r['ui'] and r['miss'] == .5)
            values = [base['serial_ms'], base['overlap_ms'], ui['overlap_ms'], miss['overlap_ms']]
            lines.append(f'| {config}/{load} | '+' | '.join(
                '/'.join(f'{x:.3f}' for x in v) for v in values)+' |')
    return '\n'.join(lines)+'\n'


def main():
    setup = {str(a): {str(extra): retimed_setup(a, extra) for extra in (0, 1)}
             for a in (11, 16)}
    result = dict(source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                       text=True).strip(),
                  input_commit='4c3a38272', setup=setup,
                  inputs=dict(triangles=T, vertices=V, refs=REFS, fragments=FRAG, quads=QUADS),
                  widths=[width_model(w) for w in (256, 128, 64)],
                  resources={str(w): resource_model(w) for w in (256, 128, 64)},
                  frames=frames(setup['11']['1']),
                  ddr_slots={str(ui): slot_capacity(ui) for ui in (False, True)})
    result['resources']['128_rf'] = resource_model(128, rf=True)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'m7-model.json').write_text(json.dumps(result, indent=2)+'\n')
    (OUT/'tables.md').write_text(tables(result))
    print(json.dumps({k: result[k] for k in ('setup', 'widths')}, indent=2))
    print((OUT/'tables.md').read_text())


if __name__ == '__main__':
    main()
