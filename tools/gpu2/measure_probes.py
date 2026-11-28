#!/usr/bin/env python3
"""Yosys generic LUT4/FF/depth reference with physical APM/RAMs as black boxes."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files


def register_depths(module):
    """Count mapped LUTs between a register/IP/port boundary and each register D."""
    drivers = {}
    aliases = {}
    cells = module['cells']
    for cell in cells.values():
        if cell['type'] == '$lut':
            for bit in cell['connections']['Y']:
                drivers[bit] = cell['connections']['A']
    for name, net in module['netnames'].items():
        if name.endswith('_r'):
            for bit in net['bits']:
                aliases.setdefault(bit, []).append(name)
    cache = {}

    def depth(bit):
        if bit not in cache:
            cache[bit] = 1+max(map(depth, drivers[bit]), default=0) if bit in drivers else 0
        return cache[bit]

    result = {}
    for cell in cells.values():
        if 'DFF' in cell['type']:
            levels = max(map(depth, cell['connections']['D']), default=0)
            for bit in cell['connections']['Q']:
                for name in aliases.get(bit, []):
                    result[name] = max(result.get(name, 0), levels)
    return result


def main():
    output = ROOT / 'build/gpu2/yosys'
    output.mkdir(parents=True, exist_ok=True)
    # Native port and parameter names match the wrappers; this is a synthesis-only model.
    apm = (ROOT / 'rtl/tech/edrv32_apm_gpu2_setup_head.v').read_text()
    params = re.findall(r'\.([A-Z][A-Z0-9_]*)\(([^\n]+)\)',
                        apm.split(') u_apm', 1)[0])
    stub = '(* blackbox *) module GTP_APM_E2 #(\n'
    stub += ',\n'.join(f'parameter {name} = {value}' for name, value in params)
    stub += ''') (
output [47:0] P, CPO,
output COUT,
output [29:0] CXO,
output [24:0] CXBO,
input [29:0] X, CXI,
input [24:0] CXBI, XB,
input [17:0] Y,
input [47:0] Z, CPI,
input CIN,
input [2:0] MODEY,
input [3:0] MODEZ,
input [4:0] MODEIN,
input CLK, CEX1, CEX2, CEX3, CEXB, CEY1, CEY2, CEZ, CEPRE, CEM, CEP,
input CEMODEY, CEMODEZ, CEMODEIN, RSTX, RSTXB, RSTY, RSTZ, RSTPRE,
input RSTM, RSTP, RSTMODEY, RSTMODEZ, RSTMODEIN);
endmodule
'''
    for name, width, address in [('ip_ram_gpu2_sdp72', 72, 9),
                                  ('ip_ram_gpu2_sdp36', 36, 10)]:
        stub += f'''(* blackbox *) module {name} (
input wr_clk, wr_rst, wr_en,
input [{address-1}:0] wr_addr,
input [{width-1}:0] wr_data,
input rd_clk, rd_rst, rd_clk_en,
input [{address-1}:0] rd_addr,
output [{width-1}:0] rd_data);
endmodule
'''
    stub += '''(* blackbox *) module ip_lutram_gpu2_setup92 (
input wr_clk, rd_clk, rst, wr_en,
input [3:0] wr_addr, rd_addr,
input [91:0] wr_data,
output [91:0] rd_data);
endmodule
'''
    (output / 'ip_stubs.v').write_text(stub)
    tops = [('setup', 'edrv32_gpu2_setup_normalize'),
            ('setup', 'edrv32_gpu2_setup_relocate'),
            ('setup', 'edrv32_apm_gpu2_setup_s49xs33'),
            ('setup', 'edrv32_fpga_probe_gpu2_setup_top'),
            ('banks', 'edrv32_fpga_probe_gpu2_banks_top'),
            ('banks_lutram', 'edrv32_fpga_probe_gpu2_banks_lutram_top')]
    result = []
    for source, top in tops:
        files = expand_files(ROOT / f'rtl/filelists/gpu2_probe_{source}.f')
        files = [name for name in files if not name.startswith('+')]
        script = f'read_verilog -lib {output / "ip_stubs.v"}\n'
        script += 'read_verilog -DFPGA_MODE -I'+str(ROOT / 'rtl/include')+' '
        script += ' '.join(files)+'\n'
        script += f'synth -top {top} -flatten -noabc\nabc -lut 4\nclean\nstat\nltp -noff\n'
        script += f'write_json {output / (top+".json")}\n'
        ys = output / (top+'.ys')
        ys.write_text(script)
        log = output / (top+'.log')
        with log.open('w') as stream:
            subprocess.run(['yosys', '-s', str(ys)], stdout=stream,
                           stderr=subprocess.STDOUT, check=True, cwd=ROOT)
        module = json.loads((output / (top+'.json')).read_text())['modules'][top]
        cells = module['cells']
        types = [cell['type'] for cell in cells.values()]
        row = dict(top=top, lut4=types.count('$lut'), ff=sum('DFF' in t for t in types),
                   apm=types.count('GTP_APM_E2'),
                   drm=types.count('ip_ram_gpu2_sdp72')+types.count('ip_ram_gpu2_sdp36'),
                   lutram_instances=types.count('ip_lutram_gpu2_setup92'))
        match = re.search(r'longest topological path.*?length=(\d+)', log.read_text(), re.I)
        row['depth'] = int(match[1])
        row['register_depths'] = register_depths(module)
        result.append(row)
        print({k: v for k, v in row.items() if k != 'register_depths'}, flush=True)
    (output / 'summary.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
