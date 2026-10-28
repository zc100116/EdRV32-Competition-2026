#!/usr/bin/env python3
# File: synth.py
# Spec: V-P2 acceptance 3; V-R1/V-R2 resource reference.
# Description: Measure media logic with external RAM wrappers blackboxed.
#              Match VIN hierarchical LUT6 and DISP flattened LUT4 baselines.
# Clock domain: host tool.
"""Run from the repository root after sourcing the edrv32 tool environment."""
from collections import Counter
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def main():
    for kind in ('vin', 'disp'):
        output = ROOT / 'build/v-p2' / kind
        output.mkdir(parents=True, exist_ok=True)
        common = ['edrv32_dma2d_rd']
        if kind == 'vin':
            common += ['edrv32_dma2d_wr', 'edrv32_sync_fifo', 'edrv32_async_fifo',
                       'edrv32_sync_fifo_ram']
            ram = 'edrv32_ram_vin_wfifo'
            commands = ['hierarchy -top edrv32_vin', 'synth -top edrv32_vin -noabc',
                        'abc -lut 6 -dress', 'opt_clean']
        else:
            common += ['edrv32_async_fifo_ram', 'edrv32_cdc_sync_bit',
                       'edrv32_cdc_handshake', 'edrv32_cdc_pulse', 'edrv32_cdc_gray_cnt']
            ram = 'edrv32_ram_disp_scan'
            commands = ['synth -top edrv32_disp -flatten -lut 4 -run begin:fine',
                        'techmap', 'opt', 'abc -lut 4', 'opt_clean']
        sources = [f'rtl/common/{name}.v' for name in common]
        sources += [p.relative_to(ROOT).as_posix()
                    for p in sorted((ROOT / f'rtl/media/{kind}').glob('*.v'))]
        script = output / 'synth.ys'
        relative = output.relative_to(ROOT).as_posix()
        script.write_text('read_verilog -lib -D SIM_MODE -Irtl/include '
                          f'rtl/tech/{ram}.v\n' +
                          'read_verilog -D SIM_MODE -Irtl/include ' + ' '.join(sources) + '\n' +
                          '\n'.join(commands) + '\n' +
                          f'write_json {relative}/netlist.json\nstat\n')
        (output / 'commit.txt').write_text(subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
        (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
        subprocess.run(['yosys', '-Q', '-T', '-l', str(output / 'synth.log'), '-s', str(script)],
                       cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        modules = json.loads((output / 'netlist.json').read_text())['modules']

        def count(name):
            cells = Counter()
            for cell in modules[name].get('cells', {}).values():
                cell_type = cell['type']
                if cell_type in modules and cell_type != ram:
                    cells.update(count(cell_type))
                else:
                    cells[cell_type] += 1
            return cells

        cells = count(f'edrv32_{kind}')
        ff = sum(n for cell_type, n in cells.items() if 'DFF' in cell_type)
        summary = f"{kind}: LUT={cells['$lut']} FF={ff} RAM={cells[ram]}\n"
        (output / 'summary.txt').write_text(summary)
        print(summary, end='', flush=True)


if __name__ == '__main__':
    main()
