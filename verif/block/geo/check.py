#!/usr/bin/env python3
# File: check.py
# Spec: CLAUDE.md 7, 9.1; V-T4 independent environment acceptance.
# Description: Apply repository style rules to SV and lint the harness with a temporary
#              port declaration in build/, as explicitly approved by the coordinator.
# Clock domain: host.
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/check'))
from regress import expand_files
from verilog_style import check


def main():
    subprocess.run(['python3', 'tools/check/verilog_style.py', str(HERE)],
                   cwd=ROOT, check=True)
    errors = []
    paths = sorted(HERE.glob('*.sv'))
    for path in paths:
        lines = path.read_text().splitlines()
        for error in check(path):
            _, line, message = error.rsplit(':', 2)
            message = message.strip()
            # CLAUDE 9.1 permits SV, initial blocks and delays in testbenches.
            if (message.startswith('forbidden syntax')
                    or message in ('initial block is forbidden in RTL',
                                   'delay is forbidden in RTL')):
                continue
            # The RTL instance regex also matches SV task/function declarations.
            if (message == 'use named port connections'
                    and lines[int(line) - 1].strip().startswith(('task ', 'function '))):
                continue
            errors.append(error)
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'GEO SV style: {len(paths)} files, 0 warnings', flush=True)
    out = ROOT / 'build/geo/lint'
    out.mkdir(parents=True, exist_ok=True)
    widths = {'clk_mem_i': 1, 'rst_mem_n_i': 1, 'irq_o': 1,
              'apb_paddr_i': 12, 'apb_psel_i': 1, 'apb_penable_i': 1,
              'apb_pwrite_i': 1, 'apb_pwdata_i': 32, 'apb_pstrb_i': 4,
              'apb_pready_o': 1, 'apb_prdata_o': 32, 'apb_pslverr_o': 1}
    channels = {
        'aw': {'id': 1, 'addr': 32, 'len': 4, 'valid': 1, 'ready': 1},
        'w': {'data': 256, 'strb': 32, 'last': 1, 'valid': 1, 'ready': 1},
        'b': {'id': 1, 'resp': 2, 'valid': 1, 'ready': 1},
        'ar': {'id': 1, 'addr': 32, 'len': 4, 'valid': 1, 'ready': 1},
        'r': {'id': 1, 'data': 256, 'resp': 2, 'last': 1, 'valid': 1, 'ready': 1},
    }
    for channel, fields in channels.items():
        for name, width in fields.items():
            master_output = (channel in ('aw', 'w', 'ar')) != (name == 'ready')
            suffix = 'o' if master_output else 'i'
            widths[f'p5_{channel}{name}_{suffix}'] = width
    wiring = (HERE / 'edrv32_geo_tb.sv').read_text().split('edrv32_geo u_geo (')[1]
    wiring = wiring.split('    );')[0]
    declarations = []
    for port in re.findall(r'\.(\w+)\(', wiring):
        width = widths[port]
        direction = 'input' if port.endswith('_i') else 'output'
        packed = f'[{width - 1}:0] ' if width > 1 else ''
        declarations.append(f'    {direction} wire {packed}{port}')
    declaration = out / 'edrv32_geo.v'
    declaration.write_text('module edrv32_geo (\n' + ',\n'.join(declarations)
                           + '\n);\nendmodule\n')
    config = out / 'stub.vlt'
    config.write_text('`verilator_config\n'
                      f'lint_off -rule UNUSEDSIGNAL -file "{declaration}"\n'
                      f'lint_off -rule UNDRIVEN -file "{declaration}"\n')
    command = ['verilator', '--lint-only', '--timing', '-Wall',
               '--timescale', '1ns/1ps', '--top-module', 'edrv32_geo_tb',
               str(config), str(declaration), *expand_files(HERE / 'support.f')]
    with (out / 'lint.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((out / 'lint.log').read_text())
        return result.returncode
    print('GEO SV lint: 0 warnings (port declaration only; no DUT functional result)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
