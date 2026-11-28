#!/usr/bin/env python3
"""Report LUT-only paths to each visible register and macro input in a Yosys JSON.

Registered APM/DRM boundaries stop the graph. Optional --start pins the source net
(and optional [bit]) so calibration can compare exactly the PDS endpoint pair.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re


def paths(filename, start=None, end=None):
    modules = json.loads(Path(filename).read_text())['modules']
    module = next(m for m in modules.values()
                  if not int(m.get('attributes', {}).get('blackbox', '0'), 2))
    aliases = {}
    for name, net in module['netnames'].items():
        if not net.get('hide_name', 0):
            for bit, node in enumerate(net['bits']):
                aliases.setdefault(node, []).append(f'{name}[{bit+net.get("offset", 0)}]')
    sources = None
    if start:
        match = re.fullmatch(r'(.+)\[(\d+)\]', start)
        net = module['netnames'][match[1] if match else start]
        sources = {net['bits'][int(match[2])-net.get('offset', 0)]} if match else set(net['bits'])
    drivers = {}
    endpoints = []
    cells = module['cells']
    for name, cell in cells.items():
        conn = cell['connections']
        if cell['type'] == '$lut':
            drivers[conn['Y'][0]] = conn['A']
        elif 'DFF' in cell['type']:
            for d, q in zip(conn['D'], conn['Q']):
                endpoints.extend((d, alias) for alias in aliases.get(q, []))
        elif cell['type'].startswith(('edrv32_', 'ip_', 'GTP_')):
            for port, direction in cell['port_directions'].items():
                if direction == 'input' and 'clk' not in port.lower():
                    endpoints.extend((node, f'{name}.{port}[{bit}]')
                                     for bit, node in enumerate(conn[port]))
    cache = {}

    def depth(node):
        if node not in cache:
            if sources is not None and node in sources:
                cache[node] = (0, aliases[node][0])
            elif node in drivers:
                prior = max((depth(n) for n in drivers[node]), key=lambda p: p[0])
                cache[node] = (prior[0]+1, prior[1]) if prior[0] >= 0 else prior
            else:
                cache[node] = (-1 if sources is not None else 0,
                               aliases.get(node, [str(node)])[0])
        return cache[node]

    result = {}
    for node, endpoint in endpoints:
        if end is not None and endpoint != end:
            continue
        level, source = depth(node)
        stem = re.sub(r'\[\d+\]$', '', endpoint)
        if level >= 0 and level > result.get(stem, {}).get('levels', -1):
            result[stem] = dict(levels=level, start=source, end=endpoint)
    types = Counter(cell['type'] for cell in cells.values())
    counts = dict(lut=types['$lut'], ff=sum(v for k, v in types.items() if 'DFF' in k),
                  apm=types['GTP_APM_E2']+2*types['edrv32_apm_gpu2_u24xu24'],
                  drm=types['ip_rom_gpu2_sfu']+types['ip_ram_gpu2_sfu_scratch'],
                  lutram=16*types['edrv32_ram_gpu2_queue']
                  + 16*types['ip_lutram_gpu2_sfu_word16']
                  + 5*types['ip_lutram_gpu2_sfu_word5'])
    return dict(resources=counts, paths=result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--start')
    parser.add_argument('--end')
    args = parser.parse_args()
    print(json.dumps(paths(args.netlist, args.start, args.end), indent=2))


if __name__ == '__main__':
    main()
