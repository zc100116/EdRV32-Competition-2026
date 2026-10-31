#!/usr/bin/env python3
# File: synth.py
# Spec: T-NPU1; npu-spec 5.4 and 7; CLAUDE.md 3.5.
# Description: Measure complete NPU LUT6, FF, logic depth and input-pin fanout.
# Clock domain: host tool; registered technology wrappers are black-box boundaries.
"""Run after sourcing env.sh; optional argument is the checkout to measure."""
from collections import Counter
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402


def measure_apb(root, output):
    commands = [f'read_verilog {root}/rtl/npu/edrv32_npu_regs.v',
                'synth -top edrv32_npu_regs -noabc', 'abc -lut 6 -dress', 'opt_clean',
                f'write_json {output}/apb.json']
    script = output / 'apb.ys'
    script.write_text('\n'.join(commands)+'\n')
    with (output / 'apb.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=root,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    module = json.loads((output / 'apb.json').read_text())['modules']['edrv32_npu_regs']
    result = {}
    for port, index in [('apb_paddr_i', 2), ('apb_pwdata_i', 0)]:
        bit = module['ports'][port]['bits'][index]
        result[f'{port}[{index}]'] = sum(bits.count(bit)
            for cell in module['cells'].values() for pin, bits in cell['connections'].items()
            if cell['port_directions'][pin] == 'input')
    (output / 'apb_loads.json').write_text(json.dumps(result, indent=2)+'\n')
    print('APB loads:', result)


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT
    output = root / 'build/npu-opt1/synth'
    output.mkdir(parents=True, exist_ok=True)
    wrappers = sorted(root.glob('rtl/tech/edrv32_*npu*.v'))
    sources = expand_files(root / 'rtl/filelists/npu.f')
    logic = [p for p in sources if not p.startswith('+') and '/rtl/tech/' not in p]
    commands = ['read_verilog -lib -D SIM_MODE -Irtl/include ' +
                ' '.join(str(p.relative_to(root)) for p in wrappers),
                'read_verilog -D SIM_MODE -Irtl/include ' + ' '.join(logic)]
    for wrapper in wrappers:
        name = wrapper.stem
        ip = name.replace('edrv32_', 'ip_', 1)
        commands += [f'rename {name} {ip}', f'chtype -set {ip} t:{name}']
    commands += ['hierarchy -check -top edrv32_npu',
                 'synth -top edrv32_npu -flatten -noabc', 'abc -lut 6 -dress',
                 'opt_clean', f'write_json {output}/netlist.json', 'stat']
    script = output / 'synth.ys'
    script.write_text('\n'.join(commands) + '\n')
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    with (output / 'synth.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=root,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    with (output / 'paths.log').open('w') as log:
        subprocess.run(['python3', str(ROOT / 'tools/synth/netlist_paths.py'),
                        str(output / 'netlist.json')], cwd=root, stdout=log, check=True)
    module = json.loads((output / 'netlist.json').read_text())['modules']['edrv32_npu']
    counts = Counter(bit for cell in module['cells'].values()
                     for port, bits in cell['connections'].items()
                     if cell['port_directions'][port] == 'input'
                     for bit in bits if isinstance(bit, int))
    clocks = {bit for name in ('clk_mem_i', 'rst_mem_n_i', 'clk_npu_i', 'rst_npu_n_i')
              for bit in module['ports'][name]['bits']}
    names = {}
    for name, net in module['netnames'].items():
        for index, bit in enumerate(net['bits']):
            label = f'{name}[{index}]'
            choice = (net['hide_name'], len(label), label)
            if isinstance(bit, int) and (bit not in names or choice < names[bit]):
                names[bit] = choice
    fanout = [(names[bit][2], count) for bit, count in counts.most_common()
              if bit not in clocks][:10]
    (output / 'fanout.json').write_text(json.dumps(fanout, indent=2)+'\n')
    print((output / 'paths.log').read_text().strip())
    for name, count in fanout:
        print(name, count)
    measure_apb(root, output)


if __name__ == '__main__':
    main()
