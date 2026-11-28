#!/usr/bin/env python3
"""m5_model.py — M-4 §3.2/3.4/3.8 risk verification, host-only, no clock domain.
Run functional ISA, static scheduling, fixed-width setup and frame planning serially.
Generated JSON/assembly/tables live under build/gpu/m5; only Python standard library.
"""
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from m5_vertex import study as vertex_study, compile_state, State, schedule
from m5_setup import precision, resources, schedule as setup_schedule
from v2_model import workload, OUT as M4_OUT

OUT = Path(__file__).resolve().parents[3] / 'build/gpu/m5'


def performance(vertex, setup, measured):
    rows = []
    for variant in ('D1', 'D8', 'G1', 'G8'):
        for name, width in (('small', 1), ('default', 2), ('full', 4)):
            c = vertex['variants'][variant]['cycles'][f'W{width}L10']
            # Identity coordinates for both enabled units are explicitly LOAD/STORE,
            # rather than silently dropping texture outputs from the lighting variant.
            state = State(lights=int(variant[1]), generic=variant.startswith('G'), texture=True)
            textured = schedule(compile_state(state), width, 10)['cycles']
            g = measured['triangles']*3*textured
            fragments = measured['perf'][4]
            p = fragments/(.5 if name == 'small' else 1.)
            refs = measured['triangle_tile_refs']
            s = refs*setup['11']['cycles']
            ddr_bytes = (measured['triangles']*3*(64+2*80)+refs*16
                         +640*360*2+fragments*16*.1)
            d = ddr_bytes/(8*.55)
            vertices_ui = measured['quads']*4
            # Screen-space UI passthrough includes position and two input textures.
            ui = vertices_ui*(32 if width == 1 else 16)
            ui += measured['quads']*2*setup['11']['cycles']
            ui += vertices_ui*(64+2*80)/(8*.55)
            if name == 'full':
                ui = 0
            serial = g+p+s+d+115200
            rows.append(dict(config=name, variant=variant, vertex_cycles=c,
                             textured_vertex_cycles=textured, geometry=g, pixel=p,
                             setup=s, ddr_bytes=ddr_bytes, ddr=d, ui_expansion=ui,
                             lower_150=max(g, p, s, d)/150000,
                             lower_200=max(g, p, s, d)/200000,
                             serial_150=serial/150000, serial_200=serial/200000,
                             with_ui_150=(serial+ui)/150000,
                             with_ui_200=(serial+ui)/200000))
    return rows


def tables(result):
    v = result['vertex']['variants']
    lines = ['| Variant | words / ALU | W1 L10 | W2 L8/10/12 | W4 L10 |',
             '|---|---:|---:|---:|---:|']
    for name, row in v.items():
        c = row['cycles']
        two = '/'.join(f'{c[f"W2L{l}"]:.2f}' for l in (8, 10, 12))
        lines.append(f'| {name} | {row["words"]}/{row["arithmetic"]} | '
                     f'{c["W1L10"]:.2f} | {two} | {c["W4L10"]:.2f} |')
    lines += ['', '| config / load | serial 150/200 ms | UI 150/200 ms |',
              '|---|---:|---:|']
    for r in result['performance']:
        lines.append(f'| {r["config"]}/{r["variant"]} | '
                     f'{r["serial_150"]:.3f}/{r["serial_200"]:.3f} | '
                     f'{r["with_ui_150"]:.3f}/{r["with_ui_200"]:.3f} |')
    return '\n'.join(lines)+'\n'


def main():
    start = time.monotonic()
    OUT.mkdir(parents=True, exist_ok=True)
    # M-4 workload builds/executes exactly one small C shared library serially.
    M4_OUT.mkdir(parents=True, exist_ok=True)
    measured = workload()
    vertex = vertex_study()
    setup = {str(n): setup_schedule(n) for n in (11, 16)}
    result = dict(source_commit=subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], text=True).strip(), vertex=vertex,
        setup_schedule=setup, setup_precision=precision(), setup_resources=resources(),
        measured_workload=measured, performance=performance(vertex, setup, measured))
    result['host'] = dict(seconds=time.monotonic()-start,
                          peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    (OUT/'m5-model.json').write_text(json.dumps(result, indent=2)+'\n')
    (OUT/'tables.md').write_text(tables(result))
    print(tables(result))
    print(json.dumps(result['host']))


if __name__ == '__main__':
    main()
