#!/usr/bin/env python3
# File: predictor_cpu.py; Spec: cpu-spec 4.4; T-CPU-V015-RTL reference measurement.
# Measure CPU resources and F1/D/E depths with asynchronous predictor RAM paths.
# Clock domain: host measurement; generated RTL copies belong to clk_sys.
"""Run from the repository root: python3 -m tools.synth.predictor_cpu OUTPUT COMMIT."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from tools.synth.netlist_paths import analyze

ROOT = Path(__file__).resolve().parents[2]


def revision_source(revision, name):
    return subprocess.check_output(['git', 'show', revision + ':' + name],
                                   cwd=ROOT, text=True)


def predictor_model(stubs, kind):
    """Model each CPU LUTRAM IP as the simple dual-port, combinational-read memory it is."""
    pattern = r'\(\* blackbox \*\) module ip_lutram_cpu_' + kind + r' \(.*?endmodule'
    match = re.search(pattern, stubs, re.S)
    header = match[0].split(');', 1)[0].replace('(* blackbox *) ', '') + ');\n'
    address_bits = int(re.search(r'\[(\d+):0\] wr_addr', header)[1]) + 1
    data_bits = int(re.search(r'\[(\d+):0\] wr_data', header)[1]) + 1
    body = (f'    reg [{data_bits - 1}:0] memory_r [0:{(1 << address_bits) - 1}];\n'
            '    assign rd_data = memory_r[rd_addr];\n'
            '    always @(posedge wr_clk) begin\n'
            '        if (wr_en)\n'
            '            memory_r[wr_addr] <= wr_data;\n'
            '    end\n')
    return stubs[:match.start()] + header + body + 'endmodule' + stubs[match.end():]


def measure_paths(design):
    module = design['modules']['edrv32_cpu_core']
    driven = {bit for cell in module['cells'].values()
              for port, bits in cell['connections'].items()
              if cell['port_directions'][port] == 'output'
              for bit in bits if isinstance(bit, int)}
    bits = sorted({bit for name, net in module['netnames'].items()
                   if name == 'u_frontend.f1_pc_r' for bit in net['bits']
                   if isinstance(bit, int) and bit in driven})
    # Named aliases can survive without drivers. Select only implemented PC FFs.
    module['ports']['measure_start'] = {'direction': 'input', 'bits': bits}
    module['netnames']['measure_start'] = {'hide_name': 0, 'bits': bits, 'attributes': {}}
    return {
        'all': analyze(design),
        'F1_query': analyze(design, starts=[r'^measure_start'],
                            ends=[r'u_frontend.f1_pc_r']),
        'D': analyze(design, ends=[r'(^|\.)e_.*_r']),
        'E': analyze(design, ends=[r'(^|\.)m_.*_r']),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('commit')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', args.commit],
                                       cwd=ROOT, text=True).strip()
    (output / 'commit.txt').write_text(revision + '\n')
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    include = output / 'rtl/include'
    include.mkdir(parents=True, exist_ok=True)
    (include / 'edrv32_build_mode.vh').write_text(
        revision_source(revision, 'rtl/include/edrv32_build_mode.vh'))
    files = []
    sources = {}
    for raw in revision_source(revision, 'rtl/filelists/cpu.f').splitlines():
        line = raw.split('//')[0].strip()
        if not line or line.startswith('+incdir+'):
            continue
        name = (ROOT / 'rtl/filelists' / line).resolve().relative_to(ROOT).as_posix()
        source = revision_source(revision, name)
        sources[name] = source
        # Preserve the PC alias only in measurement copies so its query cone is selectable.
        source = source.replace('reg [31:0] f1_pc_r;', '(* keep=1 *) reg [31:0] f1_pc_r;')
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(source)
        files.append(str(destination))
    stubs = revision_source(revision, 'tools/synth/ip_stubs.v')
    for kind in ('btb', 'direction'):
        name = 'rtl/tech/edrv32_ram_cpu_' + kind + '.v'
        if name in sources:
            stubs = predictor_model(stubs, kind)
    models = output / 'ip_models.v'
    models.write_text(stubs)
    files.append(str(models))
    commands = ['read_verilog -D FPGA_MODE -I' + str(include) + ' ' + ' '.join(files)]
    if 'parameter RVC_EN' in sources['rtl/cpu/edrv32_cpu_core.v']:
        commands.append('chparam -set RVC_EN 0 edrv32_cpu_core')
    commands += ['hierarchy -top edrv32_cpu_core', 'rename -top edrv32_cpu_core',
                 'synth_xilinx -top edrv32_cpu_core -family xc7 -flatten '
                 '-noiopad -noclkbuf -nobram',
                 f'write_json {output}/netlist.json', 'stat']
    script = output / 'synth.ys'
    script.write_text('\n'.join(commands) + '\n')
    with (output / 'synth.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)],
                       stdout=log, stderr=log, check=True)
    design = json.loads((output / 'netlist.json').read_text())
    results = measure_paths(design)
    (output / 'paths.json').write_text(json.dumps(results, indent=2) + '\n')
    print(revision, results['all']['totals'])
    print('Reference combinational levels:',
          {name: result['max_levels'] for name, result in results.items()})


if __name__ == '__main__':
    main()
