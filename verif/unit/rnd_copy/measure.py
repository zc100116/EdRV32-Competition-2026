#!/usr/bin/env python3
# File: measure.py
# Spec: T-SLIM1-MEDIA resource/logic-level acceptance; CLAUDE.md 3.5, 12.
# Description: Compare changed media modules using LUT6 synthesis and existing level analysis.
# Clock domain: host tool; no placement or physical timing claim.
"""Run from the repository root with the baseline git commit as the sole argument."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.synth.netlist_paths import analyze  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline')
    args = parser.parse_args()
    output = ROOT / 'build/slim1-media/synth'
    output.mkdir(parents=True, exist_ok=True)
    baseline = output / 'baseline'
    targets = ['rnd_copy', 'pix_kernel', 'pix_regs', 'geo_regs', 'disp_regs', 'disp_scan']
    files = [Path('rtl/media') / target.split('_')[0] / ('edrv32_' + target + '.v')
             for target in targets]
    files.append(Path('rtl/media/rnd/edrv32_rnd_decode.v'))
    for file in files:
        path = baseline / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(subprocess.check_output(['git', 'show', args.baseline + ':' + str(file)],
                                                cwd=ROOT))
    # The unchanged dedicated 512x256 RAM is a sequential boundary in both measurements.
    # ip_ identifies that boundary to tools/synth/netlist_paths.py.
    ports = ('input clk_i, wr_en_i, input [8:0] wr_addr_i, input [255:0] wr_data_i, '
             'input [31:0] wr_strb_i, input rd_en_i, input [8:0] rd_addr_i, '
             'output [255:0] rd_data_o')
    ram = output / 'ram.v'
    ram.write_text('(* blackbox *) module ip_ram_rnd_line(' + ports + '); endmodule\n' +
                   'module edrv32_ram_rnd_line(' + ports + ');\n' +
                   'ip_ram_rnd_line u_ip (' + ','.join('.' + port + '(' + port + ')'
                   for port in ['clk_i', 'wr_en_i', 'wr_addr_i', 'wr_data_i', 'wr_strb_i',
                                'rd_en_i', 'rd_addr_i', 'rd_data_o']) + '); endmodule\n')
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    summary = []
    for version in ['baseline', 'after']:
        sources = [baseline / file if version == 'baseline' else ROOT / file for file in files]
        for target in targets:
            name = 'edrv32_' + target
            dest = output / (version + '-' + target)
            commands = ['read_verilog ' + ' '.join(map(str, sources + [ram])),
                        'hierarchy -top ' + name, 'synth -top ' + name + ' -flatten -noabc',
                        'abc -lut 6 -dress', 'opt_clean',
                        'write_json ' + str(dest.with_suffix('.json')), 'stat']
            dest.with_suffix('.ys').write_text('\n'.join(commands) + '\n')
            with dest.with_suffix('.log').open('w') as log:
                subprocess.run(['yosys', '-Q', '-T', '-s', str(dest.with_suffix('.ys'))],
                               cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            result = analyze(json.loads(dest.with_suffix('.json').read_text()))
            dest.with_name(dest.name + '-paths.json').write_text(json.dumps(result, indent=2))
            summary.append(f"{version} {target}: {result['totals']}; "
                           f"max={result['max_levels']}")
            print(summary[-1], flush=True)
            if version == 'after' and target == 'rnd_copy':
                design = json.loads(dest.with_suffix('.json').read_text())
                for signal in ['wr_data_o', 'ram_rd_addr_w']:
                    filtered = analyze(design, end_nets=[signal])
                    dest.with_name(dest.name + '-' + signal + '-paths.json').write_text(
                        json.dumps(filtered, indent=2))
                    summary.append(f"after rnd_copy {signal}: {filtered['max_levels']} levels")
                    print(summary[-1], flush=True)
            if version == 'after' and target == 'pix_kernel':
                design = json.loads(dest.with_suffix('.json').read_text())
                for signal in ['s5_extreme_r', 's6_extreme_r', 's7_extreme_r']:
                    filtered = analyze(design, ends=[signal])
                    dest.with_name(dest.name + '-' + signal + '-paths.json').write_text(
                        json.dumps(filtered, indent=2))
                    summary.append(f"after pix_kernel {signal}: {filtered['max_levels']} levels")
                    print(summary[-1], flush=True)
    (output / 'summary.txt').write_text('\n'.join(summary) + '\n')


if __name__ == '__main__':
    main()
