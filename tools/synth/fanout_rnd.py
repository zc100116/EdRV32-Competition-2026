#!/usr/bin/env python3
# File: fanout_rnd.py
# Spec: T-FANOUT-RND2; rnd-spec 5/7; CLAUDE.md 12.3.
# Description: Measure RND LUT6 input-pin loads and trace their RTL sources/consumers.
#              Preserve same-edge copies; blackbox RAM wrappers and variable multipliers.
# Clock domain: host measurement; measured RTL belongs to clk_mem.
"""Source the tool environment, then run fanout_rnd.py OUTPUT [--revision COMMIT]."""
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.synth.fanout_soc import census, preserve_registers, run_yosys
from tools.synth.yosys_synth import read_filelist
from tools.rnd.timing_measure import retain_multipliers


def trace_loads(output):
    top = json.loads((output / 'hardnet.json').read_text())['modules']['edrv32_rnd']
    drivers = collections.defaultdict(list)
    consumers = collections.defaultdict(list)
    names = collections.defaultdict(list)
    for name, net in top['netnames'].items():
        for index, bit in enumerate(net['bits']):
            if isinstance(bit, int):
                names[bit].append({'net': f'{name}[{index}]',
                                   'src': net.get('attributes', {}).get('src', '')})
    for name, cell in top['cells'].items():
        for port, bits in cell['connections'].items():
            destination = consumers if cell['port_directions'][port] == 'input' else drivers
            for index, bit in enumerate(bits):
                if isinstance(bit, int):
                    destination[bit].append(f'{name}.{port}[{index}]')
    rows = [{'bit': bit, 'load': len(pins), 'nets': names[bit],
             'drivers': drivers[bit], 'consumers': pins}
            for bit, pins in consumers.items() if len(pins) >= 128]
    rows.sort(key=lambda row: row['load'], reverse=True)
    (output / 'drivers-loads.json').write_text(json.dumps(rows, indent=2) + '\n')
    counts = collections.Counter(cell['type'] for cell in top['cells'].values())
    summary = {'lut6': counts['$lut'],
               'ff': sum(n for kind, n in counts.items() if 'DFF' in kind),
               'line_ram_instances': counts['edrv32_ram_rnd_line'],
               'palette_ram_instances': counts['edrv32_ram_rnd_palette'],
               'variable_multipliers': sum(n for kind, n in counts.items()
                                           if kind.startswith('ip_hard_mul_'))}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--revision')
    args = parser.parse_args()
    output = args.output.resolve() / 'rnd'
    output.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', args.revision or 'HEAD'],
                                       cwd=ROOT, text=True).strip()
    (output / 'commit.txt').write_text(revision + ('' if args.revision else ' (working tree)') + '\n')
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    files, includes = [], set()
    if args.revision:
        filelist = subprocess.check_output(
            ['git', 'show', args.revision + ':rtl/filelists/rnd.f'], cwd=ROOT, text=True)
        for line in filelist.splitlines():
            if line.startswith('+incdir+'):
                includes.add((ROOT / 'rtl/filelists' / line[8:]).resolve().relative_to(ROOT).as_posix())
            elif line.strip():
                files.append((ROOT / 'rtl/filelists' / line).resolve().relative_to(ROOT).as_posix())
    else:
        read_filelist(ROOT / 'rtl/filelists/rnd.f', files, includes)
    commands = []
    for name in dict.fromkeys(files):
        source = (subprocess.check_output(['git', 'show', args.revision + ':' + name],
                                         cwd=ROOT, text=True)
                  if args.revision else (ROOT / name).read_text())
        source = re.sub(r'(?m)^([ \t]*)([^\n]*?) /\* synthesis syn_(?:preserve|keep)=1 \*/',
                        r'\1(* keep *) \2', source)
        blackbox = '/tech/' in name
        if blackbox:
            source = source.split(');', 1)[0] + ');\nendmodule\n'
        destination = output / Path(name).name
        destination.write_text(source)
        commands.append('read_verilog' + (' -lib' if blackbox else '') + ' -D SIM_MODE ' +
                        ' '.join('-I' + str(ROOT / path) for path in sorted(includes)) +
                        ' ' + str(destination))
    run_yosys(output, 'proc', commands + ['hierarchy -top edrv32_rnd', 'proc', 'flatten',
                                        f'write_json {output}/proc.json'])
    preserve_registers(output, 'edrv32_rnd')
    run_yosys(output, 'coarse', [f'read_json {output}/preserved.json', 'opt', 'wreduce',
                                'opt_clean', f'write_json {output}/coarse.json'])
    retain_multipliers(output, 'edrv32_rnd')
    with (output / 'hardmul.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(output / 'hardmul.ys')], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    census(output, 'edrv32_rnd')
    trace_loads(output)


if __name__ == '__main__':
    main()
