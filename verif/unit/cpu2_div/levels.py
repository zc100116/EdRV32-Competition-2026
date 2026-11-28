#!/usr/bin/env python3
# File: levels.py; Spec: CPU v2 7 / I03; Clock: host.
# Description: Report LUT6 data-cone depths at DIV stage register inputs from Yosys JSON.
import json
import sys
from functools import lru_cache

module = json.load(open(sys.argv[1]))['modules']['edrv32_cpu2_div']
drivers = {}
for cell in module['cells'].values():
    for port, direction in cell['port_directions'].items():
        if direction == 'output':
            for bit in cell['connections'][port]:
                drivers[bit] = cell


@lru_cache(None)
def depth(bit):
    cell = drivers.get(bit)
    if cell is None or cell['type'] != '$lut':
        return 0
    return 1 + max(depth(value) for value in cell['connections']['A'])


for name in ('magnitude_a_r', 'magnitude_b_r', 'difference_r', 'alignment_r',
             'zero_work_r', 'triple_b_r', 'rounds_r', 'divisor_r', 'divisor_three_r',
             'remainder_r', 'quotient_r', 'complete_data_r'):
    cones = []
    for bit in module['netnames'][name]['bits']:
        cell = drivers.get(bit)
        if cell and 'D' in cell['connections']:
            cones.extend(depth(value) for value in cell['connections']['D'])
    print(f'{name}: {max(cones)} LUT6 levels')
