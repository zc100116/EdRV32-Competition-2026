#!/usr/bin/env python3
"""CPU v2 integer LUT6 depth reference, with synchronous RAM/FF boundaries cut."""
import functools
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/cpu2_int/levels'
OUT.mkdir(parents=True, exist_ok=True)
sources = []
for line in (ROOT / 'rtl/filelists/cpu2_probe_int.f').read_text().splitlines():
    if line and not line.startswith('+'):
        sources.append(str((ROOT / 'rtl/filelists' / line).resolve()))
commands = ('read_verilog -DSIM_MODE -I' + str(ROOT / 'rtl/include') + ' ' +
            ' '.join(sources) + '; hierarchy -top edrv32_fpga_probe_cpu2_int_top; '
            'proc; opt; memory_dff; memory_collect; flatten; opt; techmap; opt; '
            'abc -lut 6; clean; write_json ' + str(OUT / 'mapped.json'))
with (OUT / 'synth.log').open('w') as log:
    subprocess.run(['yosys', '-Q', '-T', '-p', commands], stdout=log,
                   stderr=subprocess.STDOUT, check=True, cwd=ROOT)
module = json.loads((OUT / 'mapped.json').read_text())['modules'][
    'edrv32_fpga_probe_cpu2_int_top']
aliases = {}
for name, net in module['netnames'].items():
    for bit in net['bits']:
        aliases.setdefault(bit, set()).add(name)
roots = {}
drivers = {}
endpoints = []
for name, cell in module['cells'].items():
    kind = cell['type']
    ports = cell['connections']
    if 'DFF' in kind:
        for q, d in zip(ports['Q'], ports['D']):
            roots[q] = aliases.get(q, {name})
            endpoints.append((q, d))
    elif kind == '$mem_v2':
        synchronous = int(cell['parameters']['RD_CLK_ENABLE'], 2) != 0
        for bit in ports['RD_DATA']:
            if synchronous:
                roots[bit] = {name}
            else:
                # Asynchronous LUTRAM counts as one macro level after its address.
                drivers[bit] = (ports['RD_ADDR'], 1)
    elif kind == '$lut':
        for bit in ports['Y']:
            drivers[bit] = (ports['A'], 1)
    elif kind != '$scopeinfo':
        raise ValueError(f'unhandled mapped cell {name}: {kind}')

segments = [
    ('RF 4R2W', r'^rf_id_data_r$', r'^rf_(id_rs|id_owner|wb_)'),
    ('ID owner/RF/WB to AGU', r'^u_id_agu.ex_addr_r$',
     r'^id_agu_(id_candidates|id_rs1|id_imm|wb_)'),
    ('F2 bank to IB owner', r'^u_fetch.ib_candidates_r\[',
     r'^u_fetch.*u_(data|tag).memory_r$'),
    ('TAGE F2 provider/alternate', r'^tage_f2_(prediction|alternate|provider)_r$',
     r'^u_tage.*u_predict.memory_r$'),
    ('Pending to F1 hit', r'^u_tage.f2_shadow_(index|tag|direction)_r\[',
     r'^u_tage.pending_'),
    ('DRM load to operand capture', r'^u_id_agu.operand_(data|hit)_r$',
     r'^u_id_agu.*u_(data|tag).memory_r$'),
]
lines = [subprocess.check_output(['yosys', '-V'], text=True).strip(),
         'ABC LUT6 reference; sync RAM/FF outputs are roots; async LUTRAM counts 1.',
         'No Pango carry mapping, macro delay, routing or placement is modeled.']
for label, sink_pattern, source_pattern in segments:
    sink_re = re.compile(sink_pattern)
    source_re = re.compile(source_pattern)

    @functools.lru_cache(None)
    def depth(bit):
        if bit in roots:
            names = sorted(n for n in roots[bit] if source_re.search(n))
            return (0, names[0]) if names else (-10000, '')
        if bit not in drivers:
            return -10000, ''
        inputs, weight = drivers[bit]
        level, origin = max((depth(parent) for parent in inputs), default=(-10000, ''))
        return level + weight, origin

    candidates = []
    for q, d in endpoints:
        names = sorted(n for n in aliases.get(q, ()) if sink_re.search(n))
        if names:
            level, origin = depth(d)
            candidates.append((level, origin, names[0]))
    level, origin, target = max(candidates)
    if level < 0:
        raise ValueError(f'no path for {label}')
    lines.append(f'{label}: {level} levels; {origin} -> {target}')
text = '\n'.join(lines) + '\n'
(OUT / 'levels.txt').write_text(text)
print(text, end='')
