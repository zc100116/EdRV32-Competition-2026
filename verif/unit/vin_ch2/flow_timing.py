#!/usr/bin/env python3
# File: flow_timing.py
# Spec: Task V-F1; vin 2.5, 2.8.
# Description: Measure flattened VIN LUT4 depth with technology RAM blackboxes.
# Clock domain: host tool; VIN registers use clk_mem.
import json
from functools import lru_cache
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files


def main():
    out = ROOT / 'build/vin-ch2-flow/timing'
    out.mkdir(parents=True, exist_ok=True)
    commands = []
    for source in expand_files(ROOT / 'rtl/filelists/vin.f'):
        if source.endswith('.v'):
            library = '-lib ' if '/rtl/tech/' in source else ''
            commands.append(f'read_verilog {library}-D SIM_MODE -Irtl/include {source}')
    commands += ['hierarchy -check -top edrv32_vin',
                 'synth -top edrv32_vin -flatten -noabc', 'abc -lut 4', 'opt_clean',
                 f'write_json {out}/netlist.json', 'stat']
    script = out / 'netlist.ys'
    script.write_text('\n'.join(commands) + '\n')
    subprocess.run(['yosys', '-Q', '-T', '-l', str(out / 'yosys.log'), '-s', str(script)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    top = json.loads((out / 'netlist.json').read_text())['modules']['edrv32_vin']
    drivers = {cell['connections']['Y'][0]: cell['connections']['A']
               for cell in top['cells'].values() if cell['type'] == '$lut'}

    @lru_cache(None)
    def depth(bit):
        return 0 if bit not in drivers else 1 + max(map(depth, drivers[bit]), default=0)

    result = {'max_levels': max(map(depth, drivers), default=0)}
    (out / 'paths.json').write_text(json.dumps(result, indent=2) + '\n')
    print(subprocess.check_output(['yosys', '-V'], text=True).strip())
    print(f'edrv32_vin max LUT4 levels={result["max_levels"]}')


if __name__ == '__main__':
    main()
