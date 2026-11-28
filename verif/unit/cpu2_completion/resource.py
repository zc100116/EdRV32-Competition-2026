#!/usr/bin/env python3
"""Compare I04b's integrated two-issue FD logic using Yosys's XC7 reference mapping.

Run from the repository root: python3 verif/unit/cpu2_completion/resource.py
The baseline is commit 1eac54f59; the new design is the working tree. Completion,
commit and CSR are connected, and no trace ports are exported, matching unused
FPGA trace removal. Technology memories use their SIM_MODE distributed-RAM models.
This is a logic-resource reference, not Pango utilization or timing evidence.
"""
import collections
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/cpu2_completion/resource'
BASE = '1eac54f59'
MODULES = ['completion', 'commit', 'csr']


def ports(source):
    return re.findall(r'^    (input|output) wire (.*?)\b(\w+_[io]),?$', source, re.M)


def wrapper(sources):
    interface = {m: ports(source) for m, source in sources.items()}
    drivers = {}
    consumers = collections.Counter()
    widths = {}
    for module_ports in interface.values():
        for direction, width, name in module_ports:
            stem = name[:-2]
            widths[stem] = width
            if direction == 'output':
                drivers[stem] = True
            else:
                consumers[stem] += 1
    external = []
    wires = []
    for stem, width in widths.items():
        if stem not in drivers:
            external.append(f'    input wire {width}{stem}')
        elif not consumers[stem] or stem in ('age_head', 'cancel_valid', 'cancel_tag'):
            external.append(f'    output wire {width}{stem}')
        else:
            wires.append(f'    wire {width}{stem};')
    text = ('module edrv32_cpu2_i04_resource #(parameter ISSUE_WIDTH=2, '
            'parameter [31:0] FPU_FORMAT="FD") (\n' + ',\n'.join(external) + '\n);\n')
    text += '\n'.join(wires) + '\n'
    for module, module_ports in interface.items():
        text += (f'    edrv32_cpu2_{module} #(.ISSUE_WIDTH(ISSUE_WIDTH), '
                 f'.FPU_FORMAT(FPU_FORMAT)) u_{module} (\n')
        text += ',\n'.join(f'        .{name}({name[:-2]})' for _, _, name in module_ports)
        text += '\n    );\n'
    return text + 'endmodule\n'


def synth(label):
    directory = OUT / label
    directory.mkdir(parents=True, exist_ok=True)
    sources = {}
    for module in MODULES:
        path = Path(f'rtl/cpu2/edrv32_cpu2_{module}.v')
        source = (subprocess.check_output(['git', 'show', f'{BASE}:{path}'],
                                         cwd=ROOT, text=True)
                  if label == 'before' else (ROOT / path).read_text())
        sources[module] = source
        (directory / path.name).write_text(source)
    top = directory / 'edrv32_cpu2_i04_resource.v'
    top.write_text(wrapper(sources))
    rtl = [directory / f'edrv32_cpu2_{module}.v' for module in MODULES]
    rtl += [ROOT / 'rtl/tech/edrv32_ram_cpu2_completion.v', top]
    script = '\n'.join([
        'read_verilog -D SIM_MODE -I' + str(ROOT / 'rtl/include') + ' ' +
        ' '.join(map(str, rtl)),
        'synth_xilinx -top edrv32_cpu2_i04_resource -family xc7 -flatten '
        '-noiopad -noclkbuf -nobram -nosrl',
        'opt_clean', 'stat', f'write_json {directory / "xc7.json"}'])
    (directory / 'synth.ys').write_text(script + '\n')
    with (directory / 'synth.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(directory / 'synth.ys')],
                       cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    design = json.loads((directory / 'xc7.json').read_text())
    cells = collections.Counter(cell['type'] for cell in
                               design['modules']['edrv32_cpu2_i04_resource']['cells'].values())
    return {'FF': sum(count for kind, count in cells.items() if kind.startswith('FD')),
            'LUT': sum(cells[f'LUT{size}'] for size in range(1, 7)),
            'distributed_RAM_cells': sum(count for kind, count in cells.items()
                                         if kind.startswith('RAM'))}


if __name__ == '__main__':
    result = {label: synth(label) for label in ('before', 'after')}
    result['baseline'] = BASE
    result['delta'] = {key: result['after'][key] - result['before'][key]
                       for key in ('FF', 'LUT', 'distributed_RAM_cells')}
    (OUT / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
