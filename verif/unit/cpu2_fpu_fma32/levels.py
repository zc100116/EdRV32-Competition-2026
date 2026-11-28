#!/usr/bin/env python3
"""XC7 proxy depths; primitive APMs are clocked blackbox boundaries, not LUTs."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.synth.cpu_levels import worst

out = ROOT / 'build/cpu2_fpu_fma32/levels'
out.mkdir(parents=True, exist_ok=True)
ports = {'X': 30, 'Y': 18, 'Z': 48, 'CPI': 48, 'CXI': 30, 'CXBI': 25, 'XB': 25,
         'CIN': 1, 'MODEY': 3, 'MODEZ': 4, 'MODEIN': 5, 'CLK': 1,
         'P': 48, 'CPO': 48, 'COUT': 1, 'CXO': 30, 'CXBO': 25}
for name in ('CEX1 CEX2 CEX3 CEXB CEY1 CEY2 CEZ CEPRE CEM CEP CEMODEY CEMODEZ '
             'CEMODEIN RSTX RSTXB RSTY RSTZ RSTPRE RSTM RSTP RSTMODEY RSTMODEZ '
             'RSTMODEIN').split():
    ports[name] = 1
params = ['GRS_EN', 'USE_POSTADD', 'USE_PREADD', 'X_REG', 'Y_REG', 'MULT_REG',
          'P_REG', 'CPO_REG', 'USE_SIMD', 'ASYNC_RST']
stub = '(* blackbox *) module GTP_APM_E2 #(\n'
stub += ',\n'.join('parameter ' + name + ' = 0' for name in params) + '\n)(\n'
stub += ',\n'.join(('output' if name in ('P', 'CPO', 'COUT', 'CXO', 'CXBO') else 'input')
                   + f' [{width-1}:0] {name}' for name, width in ports.items())
stub += '\n); endmodule\n'
(out / 'apm_stub.v').write_text(stub)
sources = sorted((ROOT / 'rtl/cpu2/fpu').glob('*.v'))
sources += sorted((ROOT / 'rtl/tech').glob('edrv32_apm_cpu2_*.v'))
sources += [ROOT / 'fpga/rtl/edrv32_fpga_probe_cpu2_fma_top.v', out / 'apm_stub.v']
script = '\n'.join([
    'read_verilog -D FPGA_MODE -I' + str(ROOT / 'rtl/include') + ' '
    + ' '.join(map(str, sources)),
    'hierarchy -top edrv32_fpga_probe_cpu2_fma_top', 'proc', 'flatten',
    'setattr -set keep 1 w:*_r w:*_r[[]*',
    'synth_xilinx -top edrv32_fpga_probe_cpu2_fma_top -family xc7 -flatten '
    '-noiopad -noclkbuf -nobram -nosrl',
    'opt_clean', 'write_json ' + str(out / 'xc7.json'), 'stat'])
(out / 'synth.ys').write_text(script + '\n')
with (out / 'synth.log').open('w') as log:
    subprocess.run(['yosys', '-Q', '-T', '-s', str(out / 'synth.ys')],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
design = json.loads((out / 'xc7.json').read_text())
# Analyzer recognizes clocked technology IP by its ip_ prefix.
for name in list(design['modules']):
    if name == 'GTP_APM_E2':
        design['modules']['ip_GTP_APM_E2'] = design['modules'].pop(name)
for module in design['modules'].values():
    for cell in module.get('cells', {}).values():
        if cell['type'] == 'GTP_APM_E2':
            cell['type'] = 'ip_GTP_APM_E2'
summary = {}
for stage in range(1, 9):
    end = rf'u_fma\.e{stage}_.*_r' if stage < 8 else r'^(result_w|flags_w)\b'
    if stage == 2:
        end += r'|u_fma\.u_product\.u_head\.u_apm\.(X|Y)\['
    summary['E' + str(stage)] = worst(design, end=end, carry_chain_two=True)
(out / 'stages.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
