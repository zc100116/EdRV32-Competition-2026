#!/usr/bin/env python3
"""Count mapped LUT depth between registers, cutting registered tech macro boundaries.

Yosys ltp crosses blackbox cells as if they were combinational. The APM product
wrapper contains four registered boundaries, so it must be a graph cut here.
"""
from collections import Counter
import json
from pathlib import Path
import sys

for filename in sys.argv[1:]:
    module = next(v for v in json.loads(Path(filename).read_text())['modules'].values()
                  if not int(v.get('attributes', {}).get('blackbox', '0'), 2))
    cells = module['cells']
    names = {}
    priorities = {}
    for name, net in module['netnames'].items():
        if not net.get('hide_name', 0):
            for idx, node in enumerate(net['bits']):
                if isinstance(node, int):
                    priority = 3 if name.endswith('_r') else 2 if 's5_product_w' in name else 1
                    if priority > priorities.get(node, -1):
                        names[node] = f'{name}[{idx}]'
                        priorities[node] = priority
    lut_inputs = {}
    endpoints = []
    counts = Counter(cell['type'] for cell in cells.values())
    for name, cell in cells.items():
        conn = cell['connections']
        if cell['type'] == '$lut':
            lut_inputs[conn['Y'][0]] = conn['A']
        elif 'DFF' in cell['type']:
            endpoints.extend((node, names.get(q, f'{name}.Q'))
                             for node, q in zip(conn['D'], conn['Q']))
        elif cell['type'].startswith(('edrv32_', 'ip_')):
            for port, direction in cell['port_directions'].items():
                if direction == 'input' and port not in ('clk_i', 'enable_i', 'wr_en_i'):
                    endpoints.extend((node, f'{name}.{port}[{idx}]')
                                     for idx, node in enumerate(conn[port]))
    for port, data in module['ports'].items():
        if data['direction'] == 'output':
            endpoints.extend((node, f'{port}[{idx}]') for idx, node in enumerate(data['bits']))
    depths = {}
    previous = {}

    def depth(node):
        if node not in depths:
            inputs = lut_inputs.get(node)
            if inputs:
                prior = max(inputs, key=depth)
                depths[node] = depth(prior) + 1
                previous[node] = prior
            else:
                depths[node] = 0
        return depths[node]

    node, endpoint = max(endpoints, key=lambda pair: depth(pair[0]))
    levels = depth(node)
    while node in previous:
        node = previous[node]
    ff = sum(n for kind, n in counts.items() if 'DFF' in kind)
    apm = counts['edrv32_apm_gpu2_u24xu24'] * 2
    ff += counts['edrv32_apm_gpu2_u24xu24'] * 48
    drm = counts['ip_rom_gpu2_sfu'] + counts['ip_ram_gpu2_sfu_scratch']
    lr = (counts['edrv32_ram_gpu2_queue'] * 16
          + counts['ip_lutram_gpu2_sfu_word16'] * 16
          + counts['ip_lutram_gpu2_sfu_word5'] * 5)
    print(Path(filename).stem, f'LUT4={counts["$lut"]} FF={ff} APM={apm}',
          f'LUTRAM={lr} DRM={drm}',
          f'depth={levels} start={names.get(node, node)} end={endpoint}')

    # DP's two independent adder layers use this same three-edge cell.
    if Path(filename).stem == 'edrv32_gpu2_fp32_add':
        for stage, prefix in ((1, 's1_'), (2, 's2_'), (3, 'result_o')):
            choices = [(n, q) for n, q in endpoints if q.startswith(prefix)]
            endnode, endname = max(choices, key=lambda pair: depth(pair[0]))
            level = depth(endnode)
            while endnode in previous:
                endnode = previous[endnode]
            print(f'  ADD stage{stage}: depth={level} start={names.get(endnode, endnode)} '
                  f'end={endname}')
