#!/usr/bin/env python3
# File: synth.py
# Spec: Task B2-1b; vin 2.8, 7; V-R8 timing principles.
# Description: Measure LUT6/FF counts, datapath stage depths and wide enable sources.
#              Technology RAMs are blackboxes; generic results do not predict PDS timing.
# Clock domain: host tool; measured RTL is clk_mem.
from collections import Counter, defaultdict
from functools import lru_cache
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files

OUT = ROOT / 'build/vin-ch2/synth'


def run(name, commands):
    script = OUT / (name + '.ys')
    script.write_text('\n'.join(commands) + '\n')
    with (OUT / (name + '.log')).open('w') as output:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=ROOT,
                       stdout=output, stderr=subprocess.STDOUT, check=True)
    return json.loads((OUT / (name + '.json')).read_text())['modules']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'commit.txt').write_text(subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
    print(subprocess.check_output(['yosys', '-V'], text=True).strip())
    sources = []
    for source in expand_files(ROOT / 'rtl/filelists/vin.f'):
        if source.endswith('.v'):
            library = '-lib ' if '/rtl/tech/' in source else ''
            sources.append(f'read_verilog {library}-D SIM_MODE -Irtl/include {source}')
    modules = run('resource', [*sources, 'hierarchy -check -top edrv32_vin',
                              'synth -top edrv32_vin -noabc', 'abc -lut 6', 'opt_clean',
                              f'write_json {OUT}/resource.json', 'stat'])

    def count(name):
        result = Counter()
        for cell in modules[name].get('cells', {}).values():
            kind = cell['type']
            if kind in modules and not modules[kind].get('attributes', {}).get('blackbox'):
                result.update(count(kind))
            else:
                result[kind] += 1
        return result

    for name in ['edrv32_vin', 'edrv32_vin_ch2', 'edrv32_vin_ch2_data',
                 'edrv32_vin_p1_arb']:
        cells = count(name)
        print(f'{name}: LUT6={cells["$lut"]} '
              f'FF={sum(n for kind, n in cells.items() if "DFF" in kind.upper())} '
              f'line_RAM={cells["edrv32_ram_pix_line"]} '
              f'write_RAM={cells["edrv32_ram_vin_wfifo"]}')
    modules = run('stages', [*sources, 'hierarchy -check -top edrv32_vin_ch2_data',
                            'synth -top edrv32_vin_ch2_data -flatten -noabc',
                            'abc -lut 6', f'write_json {OUT}/stages.json'])
    top = modules['edrv32_vin_ch2_data']
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

    for name in ['horizontal_data_r', 'read_horizontal_r', 'write_data_r',
                 'pixel_data_r', 'pack_r', 'data_o']:
        bits = set(top['netnames'][name]['bits'])
        levels = [depth(bit) for cell in registers
                  if bits.intersection(cell['connections']['Q'])
                  for bit in cell['connections']['D']]
        print(f'{name}: max LUT6 D-input depth={max(levels, default=0)}')
    modules = run('enables', [*sources, 'hierarchy -check -top edrv32_vin',
                             'proc', 'flatten', 'opt_expr', 'opt_clean', 'opt_dff',
                             'opt_clean', f'write_json {OUT}/enables.json'])
    top = modules['edrv32_vin']
    outputs = set()
    names = defaultdict(list)
    enables = defaultdict(int)
    for name, net in top['netnames'].items():
        for bit in net['bits']:
            names[bit].append(name)
    for cell in top['cells'].values():
        if 'dff' in cell['type'].lower():
            outputs.update(cell['connections']['Q'])
            if 'EN' in cell['connections']:
                enables[cell['connections']['EN'][0]] += len(cell['connections']['Q'])
    print('CH2 enables >= 200 FF bits, before equivalent-register merging:')
    for bit, loads in sorted(enables.items(), key=lambda item: -item[1]):
        if loads >= 200 and any(name.startswith('u_ch2.') for name in names[bit]):
            label = next(name for name in names[bit] if name.startswith('u_ch2.'))
            print(f'{label}: {"REG" if bit in outputs else "COMB"} EN bits={loads}')


if __name__ == '__main__':
    main()
