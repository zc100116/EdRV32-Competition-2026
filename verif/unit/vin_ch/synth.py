#!/usr/bin/env python3
# File: synth.py
# Spec: V-R1 acceptance 3; vin 7; CLAUDE.md 4, 12.
# Description: Apply tools/synth/yosys_synth.py's hierarchical LUT6 flow to VIN.
#              The logic mode replaces only FIFO arrays with blackbox memory ports.
# Clock domain: host tool.
"""Measure VIN with behavioral storage (full) or memory blackboxes (logic)."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('full', 'logic'))
    args = parser.parse_args()
    output = ROOT / 'build/vin/synth' / args.mode
    output.mkdir(parents=True, exist_ok=True)
    files = []
    if args.mode == 'logic':
        # The FIFO's pointers, full/empty flags, CDC and count logic remain real RTL.
        for kind in ('sync', 'async'):
            path = ROOT / f'rtl/common/edrv32_{kind}_fifo.v'
            source = path.read_text()
            source = re.sub(r'    reg \[WIDTH-1:0\] memory_r \[0:DEPTH-1\];\n', '', source)
            source = re.sub(r'    assign data_o = memory_r\[.*?;\n', '', source)
            source = re.sub(r'    always @\(posedge clk[^\n]*\) begin\n'
                            r'        if \(write_w\) begin\n'
                            r'            memory_r\[.*?\n        end\n    end\n',
                            '', source, flags=re.S)
            clock = 'clk_i' if kind == 'sync' else 'clk_write_i'
            address = 'write_ptr_r' if kind == 'sync' else 'write_bin_r[PTR_WIDTH-1:0]'
            read = 'read_ptr_r' if kind == 'sync' else 'read_bin_r[PTR_WIDTH-1:0]'
            instance = (f'    vin_measure_memory #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_storage (\n'
                        f'        .clk_i({clock}), .write_i(write_w),\n'
                        f'        .write_addr_i({address}), .data_i(data_i),\n'
                        f'        .read_addr_i({read}), .data_o(data_o)\n    );\n')
            source = source.replace('endmodule', instance + 'endmodule')
            copy = output / path.name
            copy.write_text(source)
            files.append(copy.relative_to(ROOT).as_posix())
        blackbox = output / 'memory.v'
        blackbox.write_text('''(* blackbox *)
module vin_measure_memory #(parameter WIDTH=32, DEPTH=16) (
    input clk_i, input write_i,
    input [$clog2(DEPTH)-1:0] write_addr_i,
    input [WIDTH-1:0] data_i,
    input [$clog2(DEPTH)-1:0] read_addr_i,
    output [WIDTH-1:0] data_o
);
endmodule
''')
        files.append(blackbox.relative_to(ROOT).as_posix())
    else:
        files += ['rtl/common/edrv32_sync_fifo.v', 'rtl/common/edrv32_async_fifo.v']
    files += ['rtl/common/edrv32_dma2d_rd.v', 'rtl/common/edrv32_dma2d_wr.v']
    files += [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / 'rtl/media/vin').glob('*.v'))]
    relative = output.relative_to(ROOT).as_posix()
    script = output / 'synth.ys'
    script.write_text('read_verilog -D SIM_MODE -Irtl/include ' + ' '.join(files) + '\n' +
                      'hierarchy -top edrv32_vin\nsynth -top edrv32_vin -noabc\n' +
                      'abc -lut 6 -dress\nopt_clean\n' +
                      f'write_json {relative}/netlist.json\nstat\n')
    (output / 'commit.txt').write_text(subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    subprocess.run(['yosys', '-Q', '-T', '-l', str(output / 'synth.log'), '-s', str(script)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    modules = json.loads((output / 'netlist.json').read_text())['modules']

    def count(name):
        result = Counter()
        for cell in modules[name].get('cells', {}).values():
            kind = cell['type']
            if kind in modules:
                result.update(count(kind))
            else:
                result[kind] += 1
        return result

    cells = count('edrv32_vin')
    summary = (f"{args.mode}: LUT6={cells['$lut']} " +
               f"FF={sum(n for kind, n in cells.items() if 'DFF' in kind)}\n")
    (output / 'summary.txt').write_text(summary)
    print(summary, end='')


if __name__ == '__main__':
    main()
