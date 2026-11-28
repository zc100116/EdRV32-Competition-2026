#!/usr/bin/env python3
# File: measure_backend.py; cpu-v2-spec 7 and BE1; clock: host.
"""Map a fixed CPU2 probe with the same IP geometry, with/without hierarchy flattening."""
import argparse
from collections import Counter, defaultdict
import csv
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from tools.synth.yosys_synth import read_filelist
from tools.synth.netlist_paths import analyze, is_lut, is_ff, is_lutram, is_srl, is_mux, is_carry


def hierarchy_counts(design, top):
    counts = defaultdict(Counter)

    def visit(kind, owner):
        module = design['modules'][kind]
        hdlname = module.get('attributes', {}).get('hdlname', kind)
        match = re.search(r'edrv32_cpu2_\w+', hdlname)
        if match:
            owner = match[0]
        for cell in module['cells'].values():
            typ = cell['type']
            if is_lut(typ):
                category, count = 'LUT', 1
            elif is_ff(typ):
                category, count = 'FF', len(cell['connections']['Q'])
            elif is_lutram(typ):
                category, count = 'LUTRAM', 1
            elif is_srl(typ):
                category, count = 'SRL', 1
            elif is_mux(typ):
                category, count = 'MUX', 1
            elif is_carry(typ):
                category, count = 'carry', 1
            elif typ == 'INV':
                category, count = 'INV', 1
            elif typ == 'DSP48E1':
                category, count = 'APM_proxy', 1
            elif typ in design['modules']:
                child = design['modules'][typ]
                if int(child.get('attributes', {}).get('blackbox', '0'), 2):
                    category, count = 'DRM_IP', 1
                else:
                    visit(typ, owner)
                    continue
            elif typ == '$scopeinfo':
                continue
            else:
                raise ValueError('unsupported mapped cell: '+typ)
            counts[owner][category] += count

    visit(top, 'probe')
    totals = Counter()
    for count in counts.values():
        totals.update(count)
    return dict(totals=totals, by_module=counts)


def write_paths(paths, destination):
    # Source spans identify mapped cells; named aliases alone also include untraversed fanout.
    # Keep ABC provenance gaps explicit rather than assigning them to a guessed module.
    with destination.open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['rank','levels','LUT','MUX','carry','INV','start','end',
                         'known_modules','source_chain'])
        for rank, path in enumerate(paths[:20], 1):
            modules = []
            for signal in (path['start']['signal'], path['end']['signal']):
                match = re.search(r'u_core\.(u_[^.]+)', signal)
                if match and match[1] not in modules:
                    modules.append(match[1])
            for step in path['steps']:
                for location in step['src']:
                    match = re.search(r'rtl/cpu2/(?:fpu/)?edrv32_cpu2_(\w+)\.v', location)
                    if match and 'u_'+match[1] not in modules:
                        modules.append('u_'+match[1])
            chain = ' -> '.join(f"{step['src']} x{step['levels']}" for step in path['sources'])
            writer.writerow([rank,path['levels'],path['lut_levels'],path['mux_levels'],
                             path['carry_levels'],path['inv_levels'],path['start']['signal'],
                             path['end']['signal'],';'.join(modules),chain])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('width', type=int, choices=(1, 2))
    parser.add_argument('--hierarchy', action='store_true')
    args = parser.parse_args()
    top = f'edrv32_fpga_probe_cpu2_core{args.width}_top'
    out = ROOT/'build/cpu2_backend_ppa'/f'w{args.width}'/('hierarchy' if args.hierarchy else 'flatten')
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('geometry', ROOT/'fpga/scripts/measure_probe_cpu2_core.py')
    geometry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(geometry)
    models = out/'ip_models.v'
    models.write_text(geometry.ip_models())
    files, includes = [], set()
    read_filelist(ROOT/f'rtl/filelists/cpu2_probe_core{args.width}.f', files, includes)
    script = out/'synth.ys'
    script.write_text('\n'.join([
        'read_slang --allow-use-before-declare '+('--keep-hierarchy ' if args.hierarchy else '')+
        f'--top {top} -D FPGA_MODE '+
        ' '.join('-I'+p for p in sorted(includes))+' '+' '.join(files)+' '+str(models),
        f'hierarchy -check -top {top}',
        f'synth_xilinx -top {top} -family xc7 '+('' if args.hierarchy else '-flatten ')+
        '-noiopad -noclkbuf -nobram',
        'opt_clean', f'write_json {out}/xc7.json', f'tee -o {out}/stat.json stat -json',
    ])+'\n')
    (out/'version.txt').write_text(subprocess.check_output(['yosys','-V'], text=True))
    with (out/'synth.log').open('w') as log:
        subprocess.run(['yosys','-Q','-T','-s',str(script)],cwd=ROOT,stdout=log,
                       stderr=subprocess.STDOUT,check=True)
    design = json.loads((out/'xc7.json').read_text())
    if args.hierarchy:
        result = hierarchy_counts(design, top)
        (out/'modules.json').write_text(json.dumps(result,indent=2)+'\n')
    else:
        design['modules']['ip_dsp48e1'] = {'attributes': {'blackbox': '1'}}
        for cell in design['modules'][top]['cells'].values():
            if cell['type']=='DSP48E1':
                cell['type']='ip_dsp48e1'
        result = analyze(design)
        result['paths'] = result['paths'][:20]
        (out/'paths.json').write_text(json.dumps(result,indent=2)+'\n')
        write_paths(result['paths'], out/'worst20.csv')
        early = analyze(design, starts=[r'u_core\.u_lsu\.early_data_r'],
                        ends=[r'u_core\.u_alu.*skid_data_r',
                              r'u_core\.u_completion.*(?:u_data|head_data_r)'])
        early['paths'] = early['paths'][:20]
        (out/'early-result-paths.json').write_text(json.dumps(early,indent=2)+'\n')
        write_paths(early['paths'], out/'early-result-worst20.csv')
        skid = analyze(design, starts=[r'u_core\.u_lsu\.early_data_r'],
                       ends=[r'u_core\.u_alu.*skid_data_r'])
        skid['paths'] = skid['paths'][:20]
        (out/'early-skid-paths.json').write_text(json.dumps(skid,indent=2)+'\n')
        write_paths(skid['paths'], out/'early-skid-worst20.csv')
    print(json.dumps(result['totals']),flush=True)


if __name__=='__main__':
    main()
