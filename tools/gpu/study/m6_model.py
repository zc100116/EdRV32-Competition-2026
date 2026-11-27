#!/usr/bin/env python3
"""M-6 reproducible serial host study, M-4 design record section 8.
Run setup, static compiler, SFU precision and cost/frame estimates in one process.
Generated artifacts belong under build/gpu/m6; no RTL clock domain.
"""
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import m5_vertex as v
import m6_vertex as compiler
import m6_setup as setup
import m6_sfu as sfu
from v2_model import resource_model, workload, clm, add, OUT as M4_OUT

OUT = Path(__file__).resolve().parents[3]/'build/gpu/m6'


def resources():
    base = resource_model()
    result = {}
    for name in ('small', 'default', 'full'):
        rows = dict(base[name]['modules'])
        geom = list(rows['geometry'])
        # M-4 includes SFU 1500LUT/1000FF/4APM/1DRM. Replace its arithmetic;
        # 1024x96 program needs 3 DRM, plus 1 table and 1 working-set DRM.
        geom[0] += 3284-1500
        geom[1] += 1864-1000
        geom[3] = 5
        geom[4] += 384
        rows['geometry'] = geom
        rows['setup'] = setup.resource_estimate()
        total = add(rows)
        result[name] = dict(modules=rows, total=total, clm=clm(total),
                            soc_clm=clm((total[0]+36282, total[1]+30818)))
    compressed = dict(result['default']['modules'])
    compressed['geometry'] = result['small']['modules']['geometry']
    compressed['setup'] = setup.resource_estimate(contexts=1)
    result['compressed_default'] = dict(modules=compressed, total=add(compressed),
                                       clm=clm(add(compressed)))
    return result


def frames(measured):
    rows = []
    for load in ('D1', 'D8', 'G1', 'G8'):
        code = v.compile_state(v.State(lights=int(load[1]), generic=load[0] == 'G',
                                      texture=True))
        for config, width in (('small', 1), ('default', 2), ('full', 4)):
            _, _, timing = compiler.list_schedule(code, width)
            c = timing['cycles']
            triangles, refs, fragments = (measured['triangles'],
                                           measured['triangle_tile_refs'], measured['perf'][4])
            # 78 cycles/source is rounded steady service estimate, not a proven bound.
            source = 158+(triangles-1)*78
            relocation = refs*11+3
            g = triangles*3*c
            p = fragments/(.5 if width == 1 else 1)
            original_bytes = triangles*3*(64+2*80)+refs*16+640*360*2+fragments*16*.1
            plane_bytes = (triangles+refs)*288
            ddr = (original_bytes+plane_bytes)/(8*.55)
            serial = g+source+relocation+p+ddr+115200
            ui_sources = measured['quads']*2
            ui_vertices = measured['quads']*4
            ui = ui_vertices*(32 if width == 1 else 16)
            ui += 158+(ui_sources-1)*78+ui_sources*11+3
            ui += (ui_vertices*(64+2*80)+2*ui_sources*288)/(8*.55)
            if config == 'full':
                ui = 0
            rows.append(dict(config=config, load=load, textured_vertex_cycles=c,
                             source_setup=source, relocation=relocation, geometry=g, pixel=p,
                             plane_ddr_bytes=plane_bytes, ddr=ddr, ui_expansion=ui,
                             serial_150=serial/150000, serial_200=serial/200000,
                             ui_150=(serial+ui)/150000, ui_200=(serial+ui)/200000,
                             overlap_150=max(g, source+relocation, p, ddr)/150000))
    return rows


def tables(r):
    lines = ['| variant | W1 old/new | W2 old/new | W4 old/new | new SFU W2 |',
             '|---|---:|---:|---:|---:|']
    for name, row in r['vertex_m5_sfu']['variants'].items():
        values = [f'{row[w]["old_cycles"]:.2f}/{row[w]["cycles"]:.2f}'
                  for w in ('W1', 'W2', 'W4')]
        extra = r['vertex_small_sfu']['variants'][name]['W2']['cycles']
        lines.append(f'| {name} | '+ ' | '.join(values)+f' | {extra:.2f} |')
    lines += ['', '| config/load | serial 150/200 ms | UI 150/200 ms | overlap 150 |',
              '|---|---:|---:|---:|']
    for row in r['frames']:
        lines.append(f'| {row["config"]}/{row["load"]} | '
                     f'{row["serial_150"]:.3f}/{row["serial_200"]:.3f} | '
                     f'{row["ui_150"]:.3f}/{row["ui_200"]:.3f} | '
                     f'{row["overlap_150"]:.3f} |')
    lines += ['', '| module | small | default | full |', '|---|---|---|---|']
    modules = r['resources']['default']['modules']
    for name in modules:
        lines.append('| '+name+' | '+' | '.join('/'.join(map(str,
            r['resources'][c]['modules'][name])) for c in ('small', 'default', 'full'))+' |')
    for key in ('total', 'clm', 'soc_clm'):
        lines.append('| '+key+' | '+' | '.join(str(r['resources'][c][key])
                                              for c in ('small', 'default', 'full'))+' |')
    return '\n'.join(lines)+'\n'


def main():
    start = time.monotonic()
    OUT.mkdir(parents=True, exist_ok=True)
    M4_OUT.mkdir(parents=True, exist_ok=True)
    measured = workload()
    for attrs, expected in ((11, 165), (16, 213)):
        assert setup.m5.schedule(attrs)['cycles'] == expected
    result = dict(source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                       text=True).strip(),
                  measured_workload=measured, setup=setup.study(), sfu=sfu.study())
    result['vertex_m5_sfu'] = compiler.study()
    # Same complete M-5 functional/random corpus, with the compact-table arithmetic.
    old_sfu = v.sfu
    v.sfu = sfu.sfu
    result['small_sfu_m5_corpus'] = v.study()
    v.SFU_LATENCY.update(sfu.LATENCY)
    result['vertex_small_sfu'] = compiler.study()
    result['frames'] = frames(measured)
    v.sfu = old_sfu
    result['resources'] = resources()
    result['host'] = dict(seconds=time.monotonic()-start,
                          peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    (OUT/'m6-model.json').write_text(json.dumps(result, indent=2)+'\n')
    (OUT/'tables.md').write_text(tables(result))
    print(tables(result))
    print(json.dumps(result['host']))


if __name__ == '__main__':
    main()
