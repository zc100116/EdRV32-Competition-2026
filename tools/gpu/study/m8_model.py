#!/usr/bin/env python3
"""M-8 GPU geometry throughput, structural costs and frame planning estimates.
Run serially from repository root; generated JSON/tables belong under build/gpu/m8.
Standard library only; no RTL, synthesis or GPU clock measurement.
"""
import json
import math
from pathlib import Path
import resource
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import m8_vertex as vertex
import m8_setup as setup
import m7_model as m7

OUT = Path(__file__).resolve().parents[3]/'build/gpu/m8'
# Synthetic fully associative LRU reuse-distance distributions, NOT scene traces.
# None is compulsory; other distances are KiB. Capacity misses use distance >= C.
QUAD_REFS = sum(((x+15)//64-x//64+1)*((y+15)//64-y//64+1)
                for y0 in (0, 180) for i in range(1000)
                for x, y in [((i*37)%624, y0+(i*17)%164)])
PROFILES = dict(local=[(None, .01), (32, .90), (96, .05), (160, .03), (256, .01)],
                pressure=[(None, .05), (32, .50), (96, .20), (160, .20), (256, .05)])


def miss_rate(capacity, profile):
    return sum(weight for distance, weight in PROFILES[profile]
               if distance is None or distance >= capacity)


def resources(quad=False, cache=64, variant='compressed'):
    rows = {n: list(r) for n, r in m7.resource_model(64)['modules'].items()}
    # Keep M-7 clipping/project/control/SFU allocation. Two extra FP32 lanes use
    # conservative CPU-core proxies, plus a separate three-adder FP32 dot tree.
    # Remove the 768 LUT RF and charge 3R1W DRM copies and direct constant ports.
    contexts = 12
    delta = [-768+2*2749+3*656+256+(contexts-4)*32,
             2*1000+3*184+5*128+(contexts-4)*32,
             4, 3*2*math.ceil(contexts*32/512)+2*2+math.ceil((64+8*contexts)/36)-3, -768]
    rows['geometry'] = [a+b for a, b in zip(rows['geometry'], delta)]
    rows['setup'] = setup.resources(compressed=variant == 'compressed',
                                    dedicated=variant == 'dedicated')
    if quad:
        # M-4's complete existing quad allocation; retains its ordering/coverage.
        rows['quad'] = [963, 1921, 0, 0, 0]
    extra = (cache-64)//64
    # Preserve four-bank hit ports. Extra tags stay in LUTRAM, not free capacity.
    rows['texture_ram'] = [600+extra*576, 450+extra*64, 0, 16+extra*16, extra*512]
    total = m7.total(rows)
    return dict(modules=rows, total=total, gpu_clm=m7.clm(total),
                soc_clm=m7.clm((total[0]+36282, total[1]+30818)),
                clms_min=math.ceil(total[4]/4), clms_plan=math.ceil(total[4]/2.8),
                soc_clms_min=math.ceil((total[4]+1241)/4),
                soc_clms_plan=math.ceil((total[4]+1241)/2.8),
                soc_drm=total[3]+58.5, soc_apm=total[2]+4)


def frame(cycles, timing, triangles=1000, load='D1', quad=False, ui=False, miss=.1,
          scale_pixels=False):
    scale = triangles/1000
    refs, vertices = math.ceil(m7.REFS*scale), triangles*3
    fragments = m7.FRAG*scale if scale_pixels else m7.FRAG
    service = math.ceil(timing['mean'])
    geometry = vertices*cycles[load]+timing['first']+(triangles-1)*service+refs*11+3
    # 2000 UI quads' pixel work is already in the inherited fragment count.
    # Quad removes expansion; descriptor/bin costs are charged below.
    if ui and not quad:
        vertices += 8000
        refs += 4000
        geometry += 8000*16+timing['first']+3999*service+4000*11+3
        triangles += 4000
    if ui and quad:
        geometry += 2000+QUAD_REFS
    pixel = fragments+115200
    data = vertices*224+refs*16+640*360*2+fragments*16*miss+(triangles+refs)*288
    if ui and quad:
        data += 16*2000+32*QUAD_REFS
    ddr = data/4.4
    planning, serial = max(geometry, pixel)+ddr, geometry+pixel+ddr
    return dict(load=load, sources=triangles, scale_pixels=scale_pixels, quad=quad, ui=ui,
                miss=miss, geometry_cycles=geometry, pixel_cycles=pixel, ddr_bytes=data,
                overlap_ms=[planning/f for f in (150000, 200000)],
                serial_ms=[serial/f for f in (150000, 200000)],
                lower_ms=[max(geometry, pixel, ddr)/f for f in (150000, 200000)])


def pair(values):
    return '/'.join(f'{x:.3f}' for x in values)


def tables(r):
    lines = ['| vertex | M-7 W2 | M-8 W4/C12 | Mvertex/s @150/200 |',
             '|---|---:|---:|---:|']
    for name, cycles in r['cycles'].items():
        old = dict(position='—', D1=92.25, D8=161.25, G1=262, G8=1229.75)[name]
        lines.append(f'| {name} | {old} | {cycles:.6f} | {150/cycles:.3f}/{200/cycles:.3f} |')
    lines += ['', '| setup | first 11/16 | mean 11/16 | resource LUT/FF/APM/DRM/LR |',
              '|---|---:|---:|---|']
    for k in ('expanded', 'compressed', 'dedicated'):
        t = [r['setup']['timing'][str(a)][k] for a in (11, 16)]
        lines.append(f'| {k} | {t[0]["first"]}/{t[1]["first"]} | '
                     f'{t[0]["mean"]:.6f}/{t[1]["mean"]:.6f} | '
                     +'/'.join(map(str, r['setup']['resources'][k]))+' |')
    lines += ['', '| module | M-7 W64 | M-8 quad off | M-8 quad on |', '|---|---|---|---|']
    old = m7.resource_model(64)
    for n, row in r['resources']['off64']['modules'].items():
        values = [old['modules'][n], row, r['resources']['on64']['modules'][n]]
        lines.append('| '+n+' | '+' | '.join('/'.join(map(str, v)) for v in values)+' |')
    for key in ('total', 'gpu_clm', 'soc_clm', 'clms_min', 'clms_plan', 'soc_clms_min',
                'soc_clms_plan', 'soc_drm', 'soc_apm'):
        lines.append('| '+key+' | '+str(old.get(key, '—'))+' | '+
                     ' | '.join(str(r['resources'][c][key]) for c in ('off64', 'on64'))+' |')
    lines += ['', '| T / pixels | load | no UI 150/200 | UI quad off | UI quad on |',
              '|---|---|---:|---:|---:|']
    for group in r['frames']:
        lines.append(f'| {group["triangles"]} / {group["pixels"]} | {group["load"]} | '+
                     ' | '.join(pair(group[k]['overlap_ms']) for k in ('base', 'off', 'on'))+' |')
    lines += ['', '| cache KiB | local/pressure miss | UI off local | UI on local | '
              'UI off pressure | UI on pressure | LUT/FF/APM/DRM/LR off |',
              '|---|---:|---:|---:|---:|---:|---|']
    for row in r['cache']:
        lines.append(f'| {row["capacity"]} | {row["local"]:.2f}/{row["pressure"]:.2f} | '+
                     ' | '.join(pair(row[k]['overlap_ms']) for k in
                                ('off_local', 'on_local', 'off_pressure', 'on_pressure'))+' | '+
                     '/'.join(map(str, row['resource']['total']))+' |')
    t = r['vertex']['schedules']['D1']['L4C12']
    lines += ['', '| D1 reordered op | context0 issue | context11 issue |', '|---|---:|---:|']
    dynamic = [i for i in vertex.compile_state(vertex.v.State(lights=1, texture=True))
               if i.op != 'LOAD_CONST']
    for i in t['order']:
        op = dynamic[i]
        starts = [start for start, _, pc in t['trace'] if pc == i]
        lines.append(f'| {op.op} {op.key or op.dst} | {starts[0]} | {starts[-1]} |')
    return '\n'.join(lines)+'\n'


def main():
    start = time.monotonic()
    v, s = vertex.study(), setup.study()
    cycles = {n: row['L4C12']['cycles'] for n, row in v['schedules'].items()}
    r = dict(source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                  text=True).strip(),
             baseline_commit='d35387efe', quad_refs=QUAD_REFS, vertex=v, setup=s, cycles=cycles,
             resources={f'{q}{c}': resources(q == 'on', c)
                        for q in ('off', 'on') for c in (64, 128, 192)}, frames=[], cache=[])
    for triangles, scaled in ((1000, False), (5000, False), (10000, False),
                              (5000, True), (10000, True)):
        for load in ('D1', 'D8', 'G1', 'G8'):
            kwargs = dict(triangles=triangles, load=load, scale_pixels=scaled)
            r['frames'].append(dict(triangles=triangles, pixels='scaled' if scaled else 'fixed',
                                    load=load, base=frame(cycles, s['timing']['11']['compressed'],
                                                         **kwargs),
                                    off=frame(cycles, s['timing']['11']['compressed'], ui=True,
                                              **kwargs),
                                    on=frame(cycles, s['timing']['11']['compressed'], ui=True,
                                             quad=True, **kwargs)))
    for capacity in (64, 128, 192):
        row = dict(capacity=capacity, resource=resources(cache=capacity))
        for profile in PROFILES:
            miss = miss_rate(capacity, profile)
            row[profile] = miss
            for q in ('off', 'on'):
                row[q+'_'+profile] = frame(cycles, s['timing']['11']['compressed'],
                                           ui=True, quad=q == 'on', miss=miss)
        r['cache'].append(row)
    # Trace-based comparisons above exercise functional reordering and M-5 physical
    # register execution. These checks compare model outputs, not arbitrary inputs.
    assert cycles['D1'] <= 30
    assert s['timing']['11']['compressed']['mean'] <= 30
    for group in r['frames']:
        for key in ('base', 'off', 'on'):
            row = group[key]
            assert row['lower_ms'][0] <= row['overlap_ms'][0] <= row['serial_ms'][0]
    r['host'] = dict(seconds=time.monotonic()-start,
                     peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'m8-model.json').write_text(json.dumps(r, indent=2)+'\n')
    (OUT/'tables.md').write_text(tables(r))
    print((OUT/'tables.md').read_text())
    print(json.dumps(r['host']))


if __name__ == '__main__':
    main()
