#!/usr/bin/env python3
"""XC7 proxy depth by stage; carry chains count as two logical levels, not timing."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.synth.cpu_levels import worst

out = ROOT / 'build/cpu2_fpu_divsqrt/levels'
out.mkdir(parents=True, exist_ok=True)
sources = sorted((ROOT / 'rtl/cpu2/fpu').glob('edrv32_cpu2_fpu_divsqrt*.v'))
sources += [ROOT / 'rtl/cpu2/fpu/edrv32_cpu2_fpu_lz24.v',
            ROOT / 'rtl/cpu2/fpu/edrv32_cpu2_fpu_lz53.v']
script = '\n'.join([
    'read_verilog ' + ' '.join(map(str, sources)),
    'chparam -set FPU_FORMAT "FD" edrv32_cpu2_fpu_divsqrt',
    'hierarchy -top edrv32_cpu2_fpu_divsqrt', 'proc', 'flatten',
    'setattr -set keep 1 w:*_r w:*_r[[]*',
    'setattr -set keep 1 a:keep %ci1', 'select *',
    'synth_xilinx -top edrv32_cpu2_fpu_divsqrt -family xc7 -flatten '
    '-noiopad -noclkbuf -nobram -nosrl',
    'opt_clean', 'write_json ' + str(out / 'xc7.json'), 'stat'])
(out / 'synth.ys').write_text(script + '\n')
with (out / 'synth.log').open('w') as log:
    subprocess.run(['yosys', '-Q', '-T', '-s', str(out / 'synth.ys')],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
design = json.loads((out / 'xc7.json').read_text())
summary = {}
for prefix in ('u_single', 'g_double.u_double'):
    stages = {}
    for name, pattern in [
            ('prepare1', r'\.(a|b)_(mantissa|lz|exponent)_r'),
            ('prepare2', r'\.(a|b)_(normalized|adjusted)_r'),
            ('prepare3', r'\.g_(denominator[23]?|exponent)\[.*data_r'),
            ('recurrence', r'\.g_(remainder|quotient|root_trial3)\[.*data_r'),
            ('tail_shift_low', r'\.g_(partial|sticky_rem|sticky_mask|aligned_exponent)\[.*data_r'),
            ('tail_shift_high', r'\.g_(aligned|sticky)\[.*data_r'),
            ('tail_round', r'\.g_(rounded|inexact)\[.*data_r'),
            ('tail_normalize', r'\.(rounded_mantissa|rounded_exponent)_r|'
             r'\.g_(rounded_mantissa|rounded_exponent)\[.*data_r'),
            ('tail_encode', r'\.(encoded_exponent|overflow)_r|'
             r'\.g_(encoded_exponent|overflow)\[.*data_r'),
            ('tail_pack', r'\.g_result\[.*u_word.result_o|\.g_flags\[.*data_r'),
            ('control', r'\..*\[.*(enable|iterate|capture|encode|pack)_r')]:
        end = '^' + prefix.replace('.', r'\.') + '(?:' + pattern + ')'
        stages[name] = worst(design, end=end, carry_chain_two=True)
    summary[prefix] = stages
(out / 'stages.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
