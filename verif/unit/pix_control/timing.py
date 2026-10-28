#!/usr/bin/env python3
# File: timing.py
# Spec: Task V-R8; pix-spec 7; CLAUDE.md 4, 9.1.
# Description: Report local enable FF loads and before/after PIX LUT6 stage depths.
#              Generic LUT mapping is a structural reference, not PDS timing.
# Clock domain: host tool; observed RTL is clk_mem.
import argparse
from collections import defaultdict
from functools import lru_cache
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files

OUT = ROOT / 'build/media-r3/timing'


def yosys(name, lines):
    script = OUT / (name + '.ys')
    script.write_text('\n'.join(lines) + '\n')
    with (OUT / (name + '.log')).open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    return json.loads((OUT / (name + '.json')).read_text())


def enables(module):
    lines = []
    for source in expand_files(ROOT / f'rtl/filelists/{module}.f'):
        if source.endswith('.v'):
            library = '-lib ' if '/rtl/tech/' in source else ''
            lines.append(f'read_verilog {library}-D SIM_MODE -Irtl/include {source}')
    design = yosys(module, [*lines, f'hierarchy -check -top edrv32_{module}',
                           'proc', 'flatten', 'opt_expr', 'opt_clean', 'opt_dff', 'opt_clean',
                           f'write_json {OUT}/{module}.json'])
    top = design['modules'][f'edrv32_{module}']
    names = defaultdict(list)
    for name, net in top['netnames'].items():
        for index, bit in enumerate(net['bits']):
            names[bit].append(name + (f'[{index}]' if len(net['bits']) > 1 else ''))
    outputs = set()
    pin_loads = defaultdict(int)
    loads = defaultdict(int)
    for cell in top['cells'].values():
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'input' and port not in ('CLK', 'ARST'):
                weight = (len(cell['connections']['Q'])
                          if port == 'EN' and 'dff' in cell['type'].lower() else 1)
                for bit in bits:
                    pin_loads[bit] += weight
        if 'dff' in cell['type'].lower():
            outputs.update(cell['connections']['Q'])
            if 'EN' in cell['connections']:
                loads[cell['connections']['EN'][0]] += len(cell['connections']['Q'])
    # Deliberately omit opt_merge: measure the explicitly named RTL copies.
    print(f'{module}: enables={len(loads)} (FF bits on EN, before equivalent-FF merging)')
    for bit in sorted(set(loads) | {bit for bit, ns in names.items()
                                  if any(n.startswith('advance_') for n in ns)},
                      key=lambda bit: (-loads[bit], str(bit))):
        count = loads[bit]
        advance = next((name for name in names[bit] if name.startswith('advance_')), None)
        if count > 256 or advance:
            print(f'  {"REG" if bit in outputs else "COMB"} EN={count:3d} '
                  f'loads={pin_loads[bit]:3d} {advance or names[bit][0]}')


def stages(variant, directory):
    files = ['edrv32_pix.v', 'edrv32_pix_point1.v', 'edrv32_pix_regs.v',
             'edrv32_pix_filter.v', 'edrv32_pix_point2.v']
    name = 'stages-' + variant
    design = yosys(name, ['read_verilog ' + ' '.join(str(directory / f) for f in files),
                         'blackbox edrv32_pix_filter edrv32_pix_point2',
                         'hierarchy -top edrv32_pix',
                         'synth -top edrv32_pix -flatten -noabc', 'abc -lut 6',
                         f'write_json {OUT}/{name}.json'])
    top = design['modules']['edrv32_pix']
    drivers = {}
    registers = []
    for cell in top['cells'].values():
        if 'DFF' in cell['type'].upper():
            registers.append(cell)
        elif cell['type'] == '$lut':
            for bit in cell['connections']['Y']:
                drivers[bit] = cell['connections']['A']

    @lru_cache(None)
    def depth(bit):
        return 0 if bit not in drivers else 1 + max(map(depth, drivers[bit]), default=0)

    signals = ['input_data_r', 'input_contrast_r', 'input_bias_r', 'frame_cfg_r',
               'frame_contrast_r', 'frame_bias_r', 'u_point1.s1_contrast_r',
               'u_point1.bias_r[0]']
    signals += [f'u_point1.g_channel[0].{signal}' for signal in
                ['s1_center_r', 's2_unused_product_r', 's3_adjusted_r', 's4_corrected_r']]
    signals += ['u_point1.data_o']
    print(f'{variant}: LUT6 D-input depths (filters/point2 blackboxed; multiplier is LUT mapped)')
    for signal in signals:
        if signal in top['netnames']:
            bits = set(top['netnames'][signal]['bits'])
            levels = [depth(bit) for cell in registers
                      if bits.intersection(cell['connections']['Q'])
                      for bit in cell['connections']['D']]
            print(f'  {signal}: {max(levels, default=0)}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', required=True, help='Git commit for the original PIX RTL')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    baseline = OUT / 'baseline'
    baseline.mkdir(exist_ok=True)
    for filename in (ROOT / 'rtl/media/pix').glob('*.v'):
        text = subprocess.check_output(['git', 'show',
                                       f'{args.baseline}:rtl/media/pix/{filename.name}'],
                                      cwd=ROOT, text=True)
        (baseline / filename.name).write_text(text)
    for module in ['pix', 'vin', 'geo', 'disp', 'eth']:
        enables(module)
    stages('before', baseline)
    stages('after', ROOT / 'rtl/media/pix')


if __name__ == '__main__':
    main()
