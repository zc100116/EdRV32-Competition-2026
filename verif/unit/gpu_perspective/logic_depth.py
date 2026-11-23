#!/usr/bin/env python3
# File: logic_depth.py
# Spec: microarch 4.6, 4.10; coordinator R-3r timing clarification.
# Description: Report generic LUT6 depth between sequential/technology boundaries.
#              Arithmetic carry chains use generic LUTs here, not Pango carry cells.
# Clock domain: none (host).
from collections import deque
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def depth(module):
    # Every flip-flop output, primary input and opaque technology output is a root.
    drivers = {}
    inputs = {}
    for name, cell in module['cells'].items():
        if cell['type'] != '$lut':
            continue
        incoming = [bit for port, bits in cell['connections'].items()
                    if cell['port_directions'][port] == 'input' for bit in bits
                    if isinstance(bit, int)]
        inputs[name] = incoming
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'output':
                for bit in bits:
                    drivers[bit] = name
    dependencies = {name: {drivers[bit] for bit in bits if bit in drivers}
                    for name, bits in inputs.items()}
    successors = {name: [] for name in inputs}
    pending = {name: len(deps) for name, deps in dependencies.items()}
    for name, deps in dependencies.items():
        for predecessor in deps:
            successors[predecessor].append(name)
    ready = deque(name for name in inputs if pending[name] == 0)
    levels = {}
    while ready:
        name = ready.popleft()
        levels[name] = 1 + max((levels[p] for p in dependencies[name]), default=0)
        for successor in successors[name]:
            pending[successor] -= 1
            if pending[successor] == 0:
                ready.append(successor)
    if len(levels) != len(inputs):
        raise RuntimeError('combinational cycle in mapped LUT graph')
    return max(levels.values(), default=0)


def main():
    out = ROOT/'build/unit/gpu_perspective/logic'
    out.mkdir(parents=True, exist_ok=True)
    for kind in ('raster', 'quad', 'perspective'):
        sources = sorted((ROOT/'rtl/gpu').glob(f'edrv32_gpu_{kind}*.v'))
        top = 'edrv32_gpu_'+kind
        commands = ['read_verilog '+' '.join(map(str, sources))]
        if kind == 'perspective':
            commands += ['read_verilog -lib -D FPGA_MODE -I '+str(ROOT/'rtl/include')+' '+
                         str(ROOT/'rtl/tech/edrv32_rom_gpu_recip_p18.v'),
                         'blackbox edrv32_gpu_perspective_multiply']
        commands += ['hierarchy -check -top '+top, 'proc', 'flatten', 'opt_expr',
                     'opt_clean', 'memory_map', 'opt_expr', 'opt_clean', 'techmap',
                     'opt_expr', 'opt_clean', 'abc -lut 6', 'clean',
                     'write_json '+str(out/(kind+'.json'))]
        script = out/(kind+'.ys')
        script.write_text(';\n'.join(commands)+'\n')
        with (out/(kind+'.log')).open('w') as log:
            subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        design = json.loads((out/(kind+'.json')).read_text())
        print(f'{kind}: generic LUT6 maximum depth={depth(design["modules"][top])}', flush=True)


if __name__ == '__main__':
    main()
