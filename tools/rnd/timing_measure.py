#!/usr/bin/env python3
# File: timing_measure.py
# Spec: T-RND1/T-RND2; rnd-spec 5/7.
# Description: Preserve variable multipliers as hard boundaries before LUT6 mapping;
#              inspect their immediate register connections in the pre-techmap netlist.
# Clock domain: host tool; all RTL data paths measured belong to clk_mem.
import collections
import json
from pathlib import Path
import subprocess
import sys

from tools.synth.yosys_synth import read_filelist


def constant_operand(cell, port):
    return all(isinstance(bit, str) for bit in cell['connections'][port])


def retain_multipliers(output, top_name):
    design = json.loads((output / 'coarse.json').read_text())
    top = design['modules'][top_name]
    rows = []
    for name, cell in top['cells'].items():
        if cell['type'] != '$mul' or any(constant_operand(cell, p) for p in ['A', 'B']):
            continue
        kind = 'ip_hard_mul_' + str(len(rows))
        ports, nets = {}, {}
        index = 2
        for port in ['A', 'B', 'Y']:
            bits = list(range(index, index + len(cell['connections'][port])))
            index += len(bits)
            ports[port] = {'direction': 'output' if port == 'Y' else 'input', 'bits': bits}
            nets[port] = {'hide_name': 0, 'bits': bits, 'attributes': {}}
        design['modules'][kind] = {
            'attributes': {'blackbox': '1'}, 'parameter_default_values': {},
            'ports': ports, 'cells': {}, 'netnames': nets,
        }
        rows.append({
            'cell': name, 'type': kind, 'parameters': cell['parameters'],
            'widths': {p: len(b) for p, b in cell['connections'].items()},
            'src': cell.get('attributes', {}).get('src', ''),
        })
        cell['type'] = kind
        cell['parameters'] = {}
    # Reimported generated IDs must not collide with the following techmap pass.
    top['cells'] = {'timing_cell_' + str(i): c for i, c in enumerate(top['cells'].values())}
    top['netnames'] = {
        ('timing_net_' + str(i) if '$' in name else name): net
        for i, (name, net) in enumerate(top['netnames'].items())
    }
    (output / 'hardmul.json').write_text(json.dumps(design))
    (output / 'multipliers.json').write_text(json.dumps(rows, indent=2))
    (output / 'hardmul.ys').write_text(
        f'read_json {output}/hardmul.json\n'
        f'synth -top {top_name} -flatten -noabc\nabc -lut 6 -dress\nopt_clean\n'
        f'write_json {output}/hardnet.json\nstat\n')
    print('hard multipliers:', len(rows), flush=True)


def check_registers(output, top_name):
    design = json.loads((output / 'coarse.json').read_text())
    top = design['modules'][top_name]
    registers = {bit for cell in top['cells'].values() if 'dff' in cell['type'].lower()
                 for bit in cell['connections']['Q']}
    loads = collections.defaultdict(list)
    for name, cell in top['cells'].items():
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'input':
                for bit in bits:
                    if isinstance(bit, int):
                        loads[bit].append((name, cell['type'], port))
    rows, constants = [], []
    for name, cell in top['cells'].items():
        if cell['type'] != '$mul':
            continue
        consts = {p: bits for p, bits in cell['connections'].items()
                  if p in ['A', 'B'] and constant_operand(cell, p)}
        widths = {p: len(bits) for p, bits in cell['connections'].items()}
        source = cell['attributes'].get('src', '')
        if consts:
            constants.append({
                'cell': name, 'widths': widths, 'src': source,
                'constants': {p: int(''.join(bits[::-1]), 2) for p, bits in consts.items()},
            })
            continue
        pre = {p: sum(isinstance(bit, int) and bit not in registers
                      for bit in cell['connections'][p]) for p in ['A', 'B']}
        post = sorted({kind for bit in cell['connections']['Y']
                       for _, kind, _ in loads[bit] if 'dff' not in kind.lower()})
        rows.append({'cell': name, 'input_non_ff_bits': pre, 'src': source,
                     'output_non_ff_load_types': post, 'widths': widths})
    violations = [r for r in rows if any(r['input_non_ff_bits'].values())
                  or r['output_non_ff_load_types']]
    result = {'variable_multipliers': rows, 'constant_multipliers': constants,
              'violations': violations}
    (output / 'structure.json').write_text(json.dumps(result, indent=2))
    print('variable:', len(rows), 'constant:', len(constants),
          'register connection violations:', len(violations), flush=True)


def main():
    output = Path(sys.argv[1])
    top_name = sys.argv[2] if len(sys.argv) > 2 else 'edrv32_rnd'
    output.mkdir(parents=True, exist_ok=True)
    files, includes = [], set()
    read_filelist(Path('rtl/filelists/rnd.f'), files, includes)
    (output / 'stubs.v').write_text('''(* blackbox *) module ip_ram_rnd_line (
input wr_clk,wr_en,input [8:0] wr_addr,input [255:0] wr_data,
input [31:0] wr_byte_en,input wr_rst,rd_clk,rd_clk_en,rd_rst,
input [8:0] rd_addr,output [255:0] rd_data); endmodule
(* blackbox *) module ip_ram_rnd_palette (
input wr_clk,wr_en,input [8:0] wr_addr,input [31:0] wr_data,
input wr_rst,rd_clk,rd_clk_en,rd_rst,input [8:0] rd_addr,
output [31:0] rd_data); endmodule
''')
    read = 'read_verilog -D FPGA_MODE ' + ' '.join('-I' + v for v in sorted(includes))
    read += ' ' + ' '.join(files) + f' {output}/stubs.v'
    (output / 'coarse.ys').write_text(
        read + f'\nhierarchy -top {top_name}\nproc\nflatten\nopt\nwreduce\nopt_clean\n'
        f'write_json {output}/coarse.json\n')
    for stage in ['coarse', 'hardmul']:
        with (output / (stage + '.stdout')).open('w') as log:
            subprocess.run([
                'flock', '/tmp/edrv32-sim.lock', 'yosys', '-Q', '-T',
                '-l', str(output / (stage + '.log')), '-s', str(output / (stage + '.ys')),
            ], stdout=log, check=True)
        if stage == 'coarse':
            retain_multipliers(output, top_name)
            check_registers(output, top_name)
    subprocess.run([sys.executable, 'tools/synth/netlist_paths.py',
                    str(output / 'hardnet.json')], check=True)


if __name__ == '__main__':
    main()
