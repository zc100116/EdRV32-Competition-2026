#!/usr/bin/env python3
# File: fanout_cpu.py
# Spec: T-FANOUT-CPU C1-C9; CLAUDE.md 12.3.
# Description: Reproduce CPU/cache LUT6 loads and logic depths at a selected commit.
# Clock domain: host measurement; measured RTL belongs to clk_sys.
"""Run from the repository root: python3 -m tools.synth.fanout_cpu OUTPUT COMMIT."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

from tools.synth.netlist_paths import analyze
from tools.synth.yosys_synth import read_filelist


def write_paths(output, name, design, pattern, internal=False):
    module = design['modules']['edrv32_cpu_subsys']
    if internal:
        driven = {bit for cell in module['cells'].values()
                  for port, bits in cell['connections'].items()
                  if cell['port_directions'][port] == 'output'
                  for bit in bits if isinstance(bit, int)}
        driven.update(bit for port in module['ports'].values()
                      if port['direction'] == 'input'
                      for bit in port['bits'] if isinstance(bit, int))
        # Unused named wires can survive opt_clean without a driver. Internal
        # boundary measurements cover the driven, implemented portion only.
        bits = sorted({bit for net, value in module['netnames'].items()
                       if re.search(pattern, net) for bit in value['bits']
                       if isinstance(bit, int) and bit in driven})
        module['ports']['measure_end_o'] = {'direction': 'output', 'bits': bits}
    result = analyze(design, ends=['measure_end_o'] if internal else [pattern])
    if internal:
        del module['ports']['measure_end_o']
    (output / (name + '-paths.json')).write_text(json.dumps(result, indent=2) + '\n')
    return result['max_levels']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('commit')
    args = parser.parse_args()
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', args.commit], text=True).strip()
    (output / 'commit.txt').write_text(revision + '\n')
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    files, includes = [], set()
    read_filelist(Path('rtl/filelists/cpu_subsys.f'), files, includes)
    files.append('tools/synth/ip_stubs.v')
    commands = []
    for name in dict.fromkeys(files):
        source = subprocess.check_output(['git', 'show', revision + ':' + name], text=True)
        # Vendor comments are ignored by Yosys. Preserve the specified replicas
        # in measurement copies, including their driving FFs after proc/flatten.
        source = re.sub(r'(?m)^([ \t]*)([^\n]*?) /\* synthesis syn_preserve=1 \*/',
                        r'\1(* keep=1 *) \2', source)
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(source)
        commands.append('read_verilog -D FPGA_MODE ' +
                        ' '.join('-I' + path for path in sorted(includes)) +
                        ' ' + str(destination))
    commands += [
        'chparam -set RVC_EN 0 edrv32_cpu_subsys',
        'hierarchy -top edrv32_cpu_subsys', 'proc', 'flatten',
        'setattr -set keep 1 a:keep %ci1', 'select *',
        'synth -top edrv32_cpu_subsys -flatten -noabc',
        'abc -lut 6 -dress', 'opt_clean',
        f'write_json {output}/netlist.json', 'stat',
    ]
    script = output / 'synth.ys'
    script.write_text('\n'.join(commands) + '\n')
    with (output / 'synth.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    # Keep repository-relative source spans recognizable to netlist_paths.py.
    raw = (output / 'netlist.json').read_text().replace(str(output) + '/', '')
    (output / 'netlist.json').write_text(raw)
    design = json.loads(raw)
    module = design['modules']['edrv32_cpu_subsys']
    loads = Counter(bit for cell in module['cells'].values()
                    for port, bits in cell['connections'].items()
                    if cell['port_directions'][port] == 'input'
                    for bit in bits if isinstance(bit, int))
    rows = sorted(((loads[bit], name, index)
                   for name, net in module['netnames'].items()
                   for index, bit in enumerate(net['bits']) if isinstance(bit, int)),
                  reverse=True)
    (output / 'loads.tsv').write_text(''.join(
        f'{count}\t{name}[{index}]\n' for count, name, index in rows))
    (output / 'high_fanout.tsv').write_text(''.join(
        f'{count}\t{name}[{index}]\n' for count, name, index in rows if count >= 128))
    result = analyze(design)
    (output / 'paths.json').write_text(json.dumps(result, indent=2) + '\n')
    groups = [
        ('C1', r'u_core.u_frontend.f1_pc_r|u_icache.u_data[01].u_ip', False),
        ('C2', r'u_core.u_frontend.u_ib.(data_o|operand_addr_o)', True),
        ('C3', r'u_core.u_frontend.stream_w', True),
        ('C4C7', r'u_core.u_frontend.u_predictor.(direction_r|g_direction)', False),
        ('C5', r'u_core.(e_operand_load|e_advance)', True),
        ('C6', r'u_core.u_csr.(counter_r|cycle_r|instret_r|g_counter)', False),
        ('C8', r'u_icache.', False), ('C9', r'u_dcache.', False),
    ]
    levels = [(name, write_paths(output, name, design, pattern, internal))
              for name, pattern, internal in groups]
    ib_ram = analyze(design, starts=[
        r'u_core.u_frontend.u_ib.(read_ptr_r|g_read_slot.*read_ptr_r_copy|'
        r'g_operand_read.*read_ptr_r_copy)'], ends=[r'u_icache.u_data[01].u_ip'])
    (output / 'ib-ram-path.json').write_text(json.dumps(ib_ram, indent=2) + '\n')
    levels.append(('IB_RAM_CE', ib_ram['max_levels']))
    (output / 'levels.tsv').write_text(''.join(f'{name}\t{level}\n' for name, level in levels))
    print(revision, result['totals'], 'max LUT levels', result['max_levels'])
    print('Boundary LUT levels:', dict(levels))


if __name__ == '__main__':
    main()
