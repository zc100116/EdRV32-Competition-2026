#!/usr/bin/env python3
# File: fanout_soc.py
# Spec: T-FANOUT-SOC; CLAUDE.md 12.3.
# Description: LUT6 reference fanout census, with preserved scalar register copies.
#              RAM wrappers are blackboxes except the inferred W LUTRAM model.
# Clock domain: host tool; measured RTL spans the subsystem clock domains.
"""Measure subsystem input-pin fanout; source the repository tool environment first."""
import argparse
import collections
import copy
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.synth.yosys_synth import read_filelist
from tools.rnd.timing_measure import retain_multipliers

TARGETS = ['mem_subsys', 'eth', 'disp', 'vin', 'geo', 'pix', 'npu', 'sys_subsys']


def run_yosys(output, stage, commands):
    script = output / (stage + '.ys')
    script.write_text('\n'.join(commands) + '\n')
    with (output / (stage + '.log')).open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)


def preserve_registers(output, top_name):
    design = json.loads((output / 'proc.json').read_text())
    top = design['modules'][top_name]
    preserved = {bit for net in top['netnames'].values()
                 if net.get('attributes', {}).get('keep') for bit in net['bits']}
    cells = {}
    for name, cell in top['cells'].items():
        if 'dff' not in cell['type'] or not preserved.intersection(cell['connections']['Q']):
            cells[name] = cell
            continue
        # Yosys opt_dff merges identical bits inside a vector even with keep on the cell.
        # Scalarize only syn_preserve registers, then preserve each resulting FF cell.
        width = len(cell['connections']['Q'])
        for index in range(width):
            scalar = copy.deepcopy(cell)
            scalar['attributes']['keep'] = '1'
            scalar['parameters']['WIDTH'] = format(1, '032b')
            for key in ['ARST_VALUE', 'SRST_VALUE']:
                if key in scalar['parameters']:
                    scalar['parameters'][key] = cell['parameters'][key][-1-index]
            for port in ['D', 'Q']:
                scalar['connections'][port] = [cell['connections'][port][index]]
            cells[name + '_preserved_' + str(index)] = scalar
    top['cells'] = cells
    (output / 'preserved.json').write_text(json.dumps(design))


def census(output, top_name):
    top = json.loads((output / 'hardnet.json').read_text())['modules'][top_name]
    loads = collections.Counter(bit for cell in top['cells'].values()
                                for port, bits in cell['connections'].items()
                                if cell['port_directions'][port] == 'input'
                                for bit in bits if isinstance(bit, int))
    rows = sorted(((max([loads[bit] for bit in net['bits'] if isinstance(bit, int)] or [0]),
                    name, ','.join(str(loads[bit]) for bit in net['bits']))
                   for name, net in top['netnames'].items()), reverse=True)
    (output / 'loads.tsv').write_text('max_load\tnet\tbit_loads_lsb_first\n' + ''.join(
        f'{count}\t{name}\t{bits}\n' for count, name, bits in rows))
    (output / 'fanout128.tsv').write_text('max_load\tnet\n' + ''.join(
        f'{count}\t{name}\n' for count, name, _ in rows if count >= 128))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--target', choices=TARGETS, help='omit to measure all subsystems')
    parser.add_argument('--revision', help='git revision; omit to measure working tree')
    args = parser.parse_args()
    revision = args.revision or subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() + ' (working tree)'
    for target in ([args.target] if args.target else TARGETS):
        output = args.output.resolve() / target
        output.mkdir(parents=True, exist_ok=True)
        (output / 'commit.txt').write_text(revision + '\n')
        (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
        files, includes = [], set()
        read_filelist(ROOT / 'rtl/filelists' / (target + '.f'), files, includes)
        top_name = 'edrv32_' + target
        commands = []
        for name in dict.fromkeys(files):
            source = (subprocess.check_output(['git', 'show', args.revision + ':' + name],
                                             cwd=ROOT, text=True)
                      if args.revision else (ROOT / name).read_text())
            source = re.sub(r'(?m)^(\s*)((?:output\s+)?reg [^\n]*?) '
                            r'/\* synthesis syn_preserve=1 \*/', r'\1(* keep *) \2', source)
            blackbox = '/tech/' in name and 'ram_mem_xbar_w' not in name
            if blackbox:
                source = source.split(');', 1)[0] + ');\nendmodule\n'
            destination = output / Path(name).name
            destination.write_text(source)
            commands.append('read_verilog' + (' -lib' if blackbox else '') + ' -D SIM_MODE ' +
                            ' '.join('-I' + str(ROOT / path) for path in sorted(includes)) +
                            ' ' + str(destination))
        run_yosys(output, 'proc', commands + [f'hierarchy -top {top_name}', 'proc', 'flatten',
                                            f'write_json {output}/proc.json'])
        preserve_registers(output, top_name)
        run_yosys(output, 'coarse', [f'read_json {output}/preserved.json', 'opt', 'wreduce',
                                    'opt_clean', f'write_json {output}/coarse.json'])
        retain_multipliers(output, top_name)
        with (output / 'hardmul.log').open('w') as log:
            subprocess.run(['yosys', '-Q', '-T', '-s', str(output / 'hardmul.ys')], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        census(output, top_name)
        print(target + ': ' + str(output / 'loads.tsv'), flush=True)


if __name__ == '__main__':
    main()
