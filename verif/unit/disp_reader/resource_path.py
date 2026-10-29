#!/usr/bin/env python3
# File: resource_path.py
# Spec: disp-spec 7; Task D-R1 resource/path reference.
# Description: Count mapped LUT4/FF cells and list the longest memory-clock LUT path.
# Clock domain: host analysis of a Yosys generic mapped netlist.
"""Run after resource.ys: python3 verif/unit/disp_reader/resource_path.py [netlist.json]."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('netlist', nargs='?', type=Path, default=Path('build/disp_resource.json'))
source = parser.parse_args().netlist
module = json.loads(source.read_text())['modules']['edrv32_disp']
cells = module['cells']
lookup = {}
for name, net in module['netnames'].items():
    if name.startswith('$'):
        continue
    for index, bit in enumerate(net['bits']):
        if isinstance(bit, int):
            lookup.setdefault(bit, []).append(f'{name}[{index}]')


def label(bit):
    return lookup.get(bit, [str(bit)])[0]


luts = {name: cell for name, cell in cells.items() if cell['type'] == '$lut'}
ffs = {name: cell for name, cell in cells.items() if cell['type'].startswith('$_')
       and 'DFF' in cell['type']}
drivers = {cell['connections']['Y'][0]: name for name, cell in luts.items()}
mem_clock = module['ports']['clk_mem_i']['bits'][0]
cache = {}


def path_to(bit):
    if bit not in cache:
        if bit in drivers:
            cell = luts[drivers[bit]]
            longest = max((path_to(i) for i in cell['connections']['A']), key=len)
            cache[bit] = longest + [bit]
        else:
            cache[bit] = [bit]
    return cache[bit]


endpoints = []
for name, cell in ffs.items():
    if cell['connections']['C'] == [mem_clock]:
        for port in ('D', 'E'):
            if port in cell['connections']:
                bit = cell['connections'][port][0]
                endpoints.append((path_to(bit), name, port, cell['connections']['Q'][0]))
print(f'{source}: LUT4={len(luts)} FF={len(ffs)}')
for group, candidates in (
        ('clk_mem', endpoints),
        ('reader', [e for e in endpoints if any(n.startswith('u_reader.')
                   for n in lookup.get(e[3], [])) and not any(n.startswith('u_regs.')
                   for n in lookup.get(e[3], []))]),
        ('admission occupancy registers', [e for e in endpoints if any(
             n.startswith('u_reader.admission_used') for n in lookup.get(e[3], []))]),
        ('L1 row address', [e for e in endpoints if e[2] == 'D' and any(
                           n.startswith('u_reader.l1_line_base_r')
                           for n in lookup.get(e[3], []))]),
        ('descriptor outputs', [e for e in endpoints if any(n.startswith((
             'u_reader.desc_', 'u_dma.desc_base_i', 'u_dma.desc_stride_i',
             'u_dma.desc_width_bytes_i'))
                               for n in lookup.get(e[3], []))])):
    # The baseline has no L1 address registers.
    if group in ('L1 row address', 'admission occupancy registers') and not candidates:
        continue
    longest, name, port, output = max(candidates, key=lambda entry: len(entry[0]))
    print(f'{group} longest generic path: {len(longest)-1} LUT4 levels: '
          f'{label(longest[0])} -> {label(output)} ({port})')

mem_outputs = [(path_to(bit), f'{name}[{index}]')
               for name, port in module['ports'].items()
               if port['direction'] == 'output' and name != 'tmds_sym_o'
               for index, bit in enumerate(port['bits'])]
path, output = max(mem_outputs, key=lambda entry: len(entry[0]))
print(f'clk_mem output path: {len(path)-1} LUT4 levels: {label(path[0])} -> {output}')

# Isolate the new admission cone from FIFO accounting to the scheduler state.
source_bits = set()
for signal in ('u_reader.read_cnt_i', 'u_reader.read1_cnt_i',
               'u_reader.write_cnt_r', 'u_reader.write1_cnt_r',
               'u_reader.admission_used_r', 'u_reader.admission_used1_r'):
    if signal in module['netnames']:
        source_bits.update(module['netnames'][signal]['bits'])
admission_cache = {}


def admission_to(bit):
    if bit not in admission_cache:
        if bit in source_bits:
            admission_cache[bit] = [bit]
        elif bit in drivers:
            paths = [admission_to(i) for i in luts[drivers[bit]]['connections']['A']]
            paths = [p for p in paths if p]
            admission_cache[bit] = max(paths, key=len) + [bit] if paths else []
        else:
            admission_cache[bit] = []
    return admission_cache[bit]


admission_paths = [(admission_to(e[0][-1]), e[3]) for e in endpoints
                   if any(n.startswith('u_reader.state_r') for n in lookup.get(e[3], []))]
admission_paths = [e for e in admission_paths if e[0]]
# v0.2 names its scheduler's admission state line_pending_r.
if admission_paths:
    path, output = max(admission_paths, key=lambda e: len(e[0]))
    print(f'FIFO admission: {len(path)-1} LUT4 levels: '
          f'{label(path[0])} -> {label(output)}')
