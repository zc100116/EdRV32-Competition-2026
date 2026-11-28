#!/usr/bin/env python3
# File: measure.py; cpu-v2-spec 5.4/5.5; clock: host.
"""Map FE1 modules to LUT6 and report resource/path reference counts."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/synth'))
from regress import expand_files
from netlist_paths import analyze

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--analyze-only', action='store_true')
args = parser.parse_args()
out = ROOT / 'build/fe1-ppa'
out.mkdir(parents=True, exist_ok=True)
files = [('-I' + f[8:]) if f.startswith('+incdir+') else f
         for f in expand_files(ROOT / 'rtl/filelists/cpu2.f')]
for top in ('frontend', 'icache'):
    for width in (1, 2):
        name = f'{top}-w{width}'
        module = 'edrv32_cpu2_' + top
        script = 'read_verilog -D SIM_MODE ' + ' '.join(files) + '\n'
        script += f'chparam -set ISSUE_WIDTH {width} {module}\n'
        script += f'hierarchy -top {module}\n'
        script += 'synth_xilinx -flatten -noiopad -noclkbuf -nobram -top ' + module + '\n'
        script += f'write_json {out / (name + ".json")}\n'
        (out / (name + '.ys')).write_text(script)
        if not args.analyze_only:
            with (out / (name + '.log')).open('w') as stream:
                subprocess.run(['yosys', '-s', str(out / (name + '.ys'))], cwd=ROOT,
                               stdout=stream, stderr=subprocess.STDOUT, check=True)
        design = json.loads((out / (name + '.json')).read_text())
        result = {'all': analyze(design)}
        if top == 'frontend':
            result['F1'] = analyze(design, end_nets=['^ic_req_addr_o'])
            result['BTB_read_index'] = analyze(design, end_nets=[
                r'u_predictor.g_word.*read_addr_w'])
            result['BTB_write_index'] = analyze(design,
                ends=[r'u_predictor.g_word.*write_addr_w'])
            result['recovery_control'] = analyze(design,
                starts=[r'^(branch_redirect_valid_i|commit_redirect_valid_i|correction_r)$'],
                ends=[r'^(contexts_r|head_r|tail_r)(\[|$)'])
            result['JAL_decode'] = analyze(design,
                starts=[r'^ic_resp_bank.*instr_i'], ends=[r'^correction_pc_r'])
            result['restore_to_F1'] = analyze(design,
                starts=[r'^branch_redirect_(valid|pc)_i'], end_nets=['^ic_req_addr_o'])
        (out / (name + '-summary.json')).write_text(json.dumps(result, indent=2) + '\n')
        print(name, result['all']['totals'], flush=True)
