#!/usr/bin/env python3
# File: measure_probe_cpu2_core.py
# Spec: cpu-v2-spec 7; P-CORE reference measurement.
# Description: Serial XC7 resource/depth proxy with fixed CPU2 IP geometry.
# Clock domain: host; measured RTL uses clk_sys.
"""Run after sourcing env.sh: python3 fpga/scripts/measure_probe_cpu2_core.py 1 (or 2)."""
import argparse
import json
from collections import Counter
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.synth.yosys_synth import read_filelist
from tools.synth.netlist_paths import analyze, markdown

# Fixed IP geometries from rtl/tech; async RAMs are modeled, DRM remains opaque.
GEOMETRY = {
    'ip_lutram_cpu2_rf': (5, 32),
    'ip_lutram_cpu2_btb': (6, 59),
    'ip_lutram_cpu2_fast': (10, 2),
    'ip_ram_cpu2_cache_data': (11, 32),
    'ip_ram_cpu2_cache_data64': (11, 64),
    'ip_ram_cpu2_cache_tag': (9, 19),
    'ip_ram_cpu2_cache_dtag': (9, 20),
    'ip_ram_cpu2_cache_lru': (9, 1),
    'ip_ram_cpu2_tage': (8, 16),
    'ip_ram_cpu2_tage_train': (9, 16),
    'ip_ram_cpu2_base': (11, 2),
    'ip_ram_cpu2_base_train': (12, 2),
}


def ip_models():
    lines = []
    for name, (address, width) in GEOMETRY.items():
        asynchronous = name.startswith('ip_lutram')
        ports = ['input wr_clk', 'input wr_en', f'input [{address-1}:0] wr_addr',
                 f'input [{width-1}:0] wr_data', 'input rd_clk',
                 f'input [{address-1}:0] rd_addr', f'output [{width-1}:0] rd_data']
        if asynchronous:
            ports.append('input rst')
        else:
            ports += ['input wr_rst', 'input rd_rst', 'input rd_clk_en']
        if name.endswith('data64'):
            ports.append('input [7:0] wr_byte_en')
        lines.append(('' if asynchronous else '(* blackbox *) ') +
                     f'module {name} (\n' + ',\n'.join(ports) + '\n);')
        if asynchronous:
            lines += [f'reg [{width-1}:0] memory_r [0:{(1<<address)-1}];',
                      'assign rd_data = memory_r[rd_addr];',
                      'always @(posedge wr_clk) if (wr_en) memory_r[wr_addr] <= wr_data;']
            if name.endswith('fast'):
                lines += ['integer entry;', f'initial for (entry=0; entry<{1<<address}; entry=entry+1)',
                          "    memory_r[entry] = 2'd1;"]
        lines.append('endmodule')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('issue', type=int, choices=(1, 2))
    args = parser.parse_args()
    top = f'edrv32_fpga_probe_cpu2_core{args.issue}_top'
    output = ROOT / 'build/probe_cpu2_core' / f'core{args.issue}'
    output.mkdir(parents=True, exist_ok=True)
    models = output / 'ip_models.v'
    models.write_text(ip_models())
    files, includes = [], set()
    read_filelist(ROOT / f'rtl/filelists/cpu2_probe_core{args.issue}.f', files, includes)
    script = output / 'synth.ys'
    script.write_text('\n'.join([
        f'read_slang --allow-use-before-declare --top {top} -D FPGA_MODE ' +
        ' '.join('-I' + p for p in sorted(includes)) +
        ' ' + ' '.join(files) + ' ' + str(models),
        f'hierarchy -check -top {top}',
        f'synth_xilinx -top {top} -family xc7 -flatten -noiopad -noclkbuf -nobram',
        'opt_clean', f'write_json {output}/xc7.json', 'stat',
    ]) + '\n')
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    (output / 'commit.txt').write_text(subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
    with (output / 'synth.log').open('w') as stream:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=ROOT,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    design = json.loads((output / 'xc7.json').read_text())
    cells = design['modules'][top]['cells']
    census = Counter(cell['type'] for cell in cells.values())
    # DSP pipeline placement is opaque in this depth proxy, just like fixed DRM IP.
    # Preserve the raw mapped JSON; only the analysis view treats DSP pins as boundaries.
    design['modules']['ip_dsp48e1'] = {'attributes': {'blackbox': '1'}}
    for cell in cells.values():
        if cell['type'] == 'DSP48E1':
            cell['type'] = 'ip_dsp48e1'
    result = analyze(design)
    result['mapped_cell_counts'] = dict(census)
    (output / 'paths.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'paths.md').write_text(markdown(result, limit=10))
    print(json.dumps({'top': top, 'totals': result['totals'],
                      'max_levels': result['max_levels'], 'output': str(output)}, indent=2))


if __name__ == '__main__':
    main()
