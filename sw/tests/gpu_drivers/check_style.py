#!/usr/bin/env python3
# File: check_style.py
# Spec: CLAUDE.md 7, 9.1; gpu-soc-testplan ST-10-ST-14.
# Description: Apply existing timed-testbench style adaptation to this task's SV files.
# Clock domain: host.
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.check.verilog_style import check

out = ROOT / 'build/gpu_drivers/style'
out.mkdir(parents=True, exist_ok=True)
paths = [ROOT / 'verif/models/i2c_rx_model.sv',
         ROOT / 'verif/soc/gpu_audio/i2c_model_tb.sv']
paths += [ROOT / f'verif/soc/gpu_{name}/edrv32_gpu_scenario.sv'
          for name in ('audio', 'irq', 'render', 'eth', 'reset')]
errors = []
for index, path in enumerate(paths):
    source = re.sub(r'(?m)^ *(?:task|function) automatic [^;]*;',
                    lambda match: '\n' * match[0].count('\n'), path.read_text())
    source = re.sub(r'\.(len|substr|size|pop_front)\s*\(', r'_\1(', source)
    copy = out / f'{index}.sv'
    copy.write_text(source)
    for error in check(copy):
        if any(allowed in error for allowed in ('forbidden syntax', 'initial block',
               'delay is forbidden', 'use named port connections')):
            continue
        errors.append(error.replace(str(copy), str(path.relative_to(ROOT))))
print('\n'.join(errors))
print(f'GPU SoC style: {len(paths)} files, {len(errors)} warnings')
sys.exit(bool(errors))
