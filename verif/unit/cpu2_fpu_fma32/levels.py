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

BASELINE = '8344727fcb67127837ab6c02679f81e512be006b'
summary = {}
for version in ('before', 'after'):
    target = out / version
    target.mkdir(exist_ok=True)
    relative = ['rtl/cpu2/fpu/edrv32_cpu2_fpu_' + name + '.v'
                for name in ('fma32', 'lz24', 'lza32')]
    relative += ['rtl/tech/edrv32_apm_cpu2_' + name + '.v'
                 for name in ('head', 'shift16', 'u24xu24')]
    sources = []
    for name in relative:
        if version == 'before':
            source = target / Path(name).name
            source.write_bytes(subprocess.check_output(['git', 'show', BASELINE + ':' + name]))
        else:
            source = ROOT / name
        sources.append(source)
    sources.append(out / 'apm_stub.v')
    script = '\n'.join([
        'read_verilog -D FPGA_MODE -I' + str(ROOT / 'rtl/include') + ' '
        + ' '.join(map(str, sources)),
        'hierarchy -top edrv32_cpu2_fpu_fma32', 'proc', 'flatten',
        'setattr -set keep 1 w:*_r w:*_r[[]*',
        'synth_xilinx -top edrv32_cpu2_fpu_fma32 -family xc7 -flatten '
        '-noiopad -noclkbuf -nobram -nosrl',
        'opt_clean', 'write_json ' + str(target / 'xc7.json'), 'stat'])
    (target / 'synth.ys').write_text(script + '\n')
    with (target / 'synth.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(target / 'synth.ys')],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    design = json.loads((target / 'xc7.json').read_text())
    for name in list(design['modules']):
        if name == 'GTP_APM_E2':
            design['modules']['ip_GTP_APM_E2'] = design['modules'].pop(name)
    for module in design['modules'].values():
        for cell in module.get('cells', {}).values():
            if cell['type'] == 'GTP_APM_E2':
                cell['type'] = 'ip_GTP_APM_E2'
    cells = design['modules']['edrv32_cpu2_fpu_fma32']['cells']
    counts = {}
    for cell in cells.values():
        counts[cell['type']] = counts.get(cell['type'], 0) + 1
    stages = {}
    for stage in range(1, 8):
        stages['E' + str(stage)] = worst(design, end=rf'e{stage}_.*_r', carry_chain_two=True)
    stages['round/skid'] = worst(design, end=r'skid_data_r|^result_o', carry_chain_two=True)
    summary[version] = {'counts': counts, 'stages': stages}
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
