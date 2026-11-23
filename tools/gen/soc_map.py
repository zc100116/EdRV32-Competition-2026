#!/usr/bin/env python3
# File: soc_map.py
# Spec: edrv32-soc-spec 6.1; gpu-soc-spec 6.1; infra-plan I-05
# Description: Generate RTL/C constants and the address table from the shared JSON.
#              Generated output follows source order for repeatable builds.
# Clock domain: none (host tool).
"""Generate SoC address constants and the build/ address table (SoC spec 6.1)."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


# Map name -> (source JSON, Verilog header, C header, build table, spec reference).
MAPS = {
    'vision': ('soc_address_map.json', 'edrv32_soc_map.vh', 'soc_map.h', 'soc_address_map.md',
               'edrv32-soc-spec 6.1'),
    'gpu': ('gpu_soc_address_map.json', 'edrv32_gpu_soc_map.vh', 'gpu_soc_map.h',
            'gpu_soc_address_map.md', 'gpu-soc-spec 6.1'),
}


def generate(map_name):
    source, vh_name, h_name, md_name, spec = MAPS[map_name]
    data = json.loads((ROOT / 'rtl/include' / source).read_text())
    constants = [('CLK_SYS_HZ', data['clk_sys_hz'])]
    table = ['# SoC address map', '', 'Source: SoC specification 6.1 and '
             f'`rtl/include/{source}`.', '',
             '| Region | Base | Size | Cacheable | Executable | Read | Write |',
             '|---|---|---|---|---|---|---|']
    for region in data['regions']:
        name = region['name']
        constants.extend([(name + '_BASE', int(region['base'], 0)),
                          (name + '_SIZE', int(region['size'], 0))])
        for field in ('cacheable', 'executable', 'readable', 'writable'):
            constants.append((name + '_' + field.upper(), int(region[field])))
        attrs = ['yes' if region[field] else 'no'
                 for field in ('cacheable', 'executable', 'readable', 'writable')]
        table.append('| ' + ' | '.join([region['description'], region['base'],
                                       region['size']] + attrs) + ' |')
    slot_size = int(data['apb_slot_size'], 0)
    constants.append(('APB_SLOT_SIZE', slot_size))
    for group, base_name in [('system_apb_slots', 'SYS_APB'),
                             ('media_apb_slots', 'MEDIA_APB')]:
        base = next(int(item['base'], 0) for item in data['regions']
                    if item['name'] == base_name)
        table.extend(['', '## ' + base_name, '', '| Slot | Name | Base |', '|---|---|---|'])
        for slot in data[group]:
            address = base + slot['slot'] * slot_size
            table.append(f'| {slot["slot"]} | {slot["name"]} | 0x{address:08X} |')
            if slot['name'] != 'RESERVED':
                constants.extend([(slot['name'] + '_SLOT', slot['slot']),
                                  (slot['name'] + '_BASE', address)])
    table.extend(['', '## PLIC sources', '', '| Source | Name |', '|---|---|'])
    for source in data['plic_sources']:
        table.append(f'| {source["source"]} | {source["name"]} |')
        if source['name'] != 'RESERVED':
            constants.append(('PLIC_SOURCE_' + source['name'], source['source']))
    verilog = [f'// File: {vh_name}', f'// Spec: {spec}',
               '// Description: Generated address, attribute, APB slot and interrupt constants.',
               '//              Include inside a module; regenerate with tools/gen/soc_map.py.',
               '// Clock domain: none (constants).']
    guard = 'EDRV32_' + h_name.replace('.', '_').upper()
    header = [f'/* File: {h_name}', f' * Spec: {spec}',
              ' * Description: Generated SoC addresses, attributes, slots and interrupt sources.',
              ' *              Regenerate with tools/gen/soc_map.py.',
              ' * Clock domain: none (constants).', ' */',
              f'#ifndef {guard}', f'#define {guard}', '']
    for name, value in constants:
        verilog.append(f'localparam [31:0] EDRV32_{name} = 32\'h{value:08X};')
        header.append(f'#define EDRV32_{name} 0x{value:08X}u')
    header.extend(['', '#endif'])
    for target, lines in [('rtl/include/' + vh_name, verilog),
                          ('sw/bsp/include/' + h_name, header),
                          ('build/' + md_name, table)]:
        path = ROOT / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    generate(sys.argv[1] if len(sys.argv) > 1 else 'vision')
