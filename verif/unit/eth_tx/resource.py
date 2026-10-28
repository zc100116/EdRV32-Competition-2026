#!/usr/bin/env python3
# File: resource.py
# Spec: eth 7; CLAUDE.md 1.4.
# Description: Generic LUT6 reference mapping with technology RAM wrappers as black boxes.
# Clock domain: none (host tool).
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

out = ROOT / 'build/eth/resource'
out.mkdir(parents=True, exist_ok=True)
files = expand_files(ROOT / 'rtl/filelists/eth.f')
includes = [item.replace('+incdir+', '-I') for item in files if item.startswith('+incdir+')]
tech = [item for item in files if '/tech/' in item]
rtl = [item for item in files if not item.startswith('+') and item not in tech]
read = 'read_verilog -D SIM_MODE ' + ' '.join(includes) + ' '
tops = ['edrv32_eth', 'edrv32_eth_rx', 'edrv32_eth_rx_write', 'edrv32_eth_tx',
        'edrv32_eth_regs', 'edrv32_eth_mdio', 'edrv32_eth_rx_front',
        'edrv32_eth_tx_front', 'edrv32_eth_fifo', 'edrv32_dma2d_wr']
summary = {}
for top in tops:
    script = out / (top + '.ys')
    script.write_text('\n'.join([
        'read_verilog -lib -D SIM_MODE ' + ' '.join(includes + tech),
        read + ' '.join(rtl), 'hierarchy -top ' + top,
        'synth -top ' + top + ' -flatten -noabc',
        'abc -lut 6 -dress', 'opt_clean',
        'write_json ' + str(out / (top + '.json')), 'stat']) + '\n')
    with (out / (top + '.log')).open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    netlist = json.loads((out / (top + '.json')).read_text())
    cells = netlist['modules'][top]['cells']
    summary[top] = sum(cell['type'] == '$lut' for cell in cells.values())
    print(top, summary[top], flush=True)
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
