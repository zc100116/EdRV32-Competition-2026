#!/usr/bin/env python3
# File: synth.py
# Spec: npu-spec 5.6, 7; CLAUDE.md 3.5.
# Description: Reproduce generic NPU resource delta and mapped post levels/fanout.
# Clock domain: host; PG2L200H timing remains a Windows PDS measurement.
"""Run from the repository after sourcing env.sh; no physical timing claim."""
from collections import Counter
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files
from tools.synth.cpu_levels import worst
from tools.synth.netlist_paths import analyze

BASELINE = 'fa3f9312'
OUT = ROOT / 'build/npu_post/measure'


def synthesize(source, label, post_only, xc7, preserve=True):
    wrappers = sorted((source / 'rtl/tech').glob('edrv32_*npu*.v'))
    if post_only:
        wrappers = sorted((source / 'rtl/tech').glob('edrv32_ram_npu_post_*.v'))
        files = sorted((source / 'rtl/npu').glob('edrv32_npu_post*.v'))
        files.append(source / 'rtl/common/edrv32_reset_copy.v')
    else:
        files = [Path(p) for p in expand_files(source / 'rtl/filelists/npu.f')
                 if not p.startswith('+') and '/rtl/tech/' not in p]
    relative = lambda paths: ' '.join(str(p.relative_to(source)) for p in paths)
    commands = ['read_verilog -lib -D SIM_MODE -Irtl/include ' + relative(wrappers),
                'read_verilog -D SIM_MODE -Irtl/include ' + relative(files)]
    for wrapper in wrappers:
        name = wrapper.stem
        ip = name.replace('edrv32_', 'ip_', 1)
        commands += [f'rename {name} {ip}', f'chtype -set {ip} t:{name}']
    top = 'edrv32_npu_post' if post_only else 'edrv32_npu'
    commands += [f'hierarchy -check -top {top}']
    if preserve:
        commands += ['setattr -set keep 1 edrv32_reset_copy/w:rst_n_o', 'select *',
                     'proc', 'setattr -set keep 1 a:keep %ci1', 'select *', 'flatten',
                     'setattr -set keep 1 a:keep %ci1', 'select *']
    else:
        commands += ['proc', 'flatten', 'setattr -unset keep',
                     'setattr -unset syn_preserve', 'select *']
    if xc7:
        commands += [f'synth_xilinx -top {top} -family xc7 -flatten '
                     '-noiopad -noclkbuf -nobram -nosrl']
    else:
        commands += [f'synth -top {top} -flatten -noabc', 'abc -lut 6']
    commands += ['opt_clean', f'write_json {OUT}/{label}.json', 'stat']
    script = OUT / f'{label}.ys'
    script.write_text('\n'.join(commands) + '\n')
    with (OUT / f'{label}.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], cwd=source,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    design = json.loads((OUT / f'{label}.json').read_text())
    cells = Counter(c['type'] for c in design['modules'][top]['cells'].values())
    result = dict(LUT=sum(v for k, v in cells.items() if k == '$lut' or k.startswith('LUT')),
                  FF=sum(v for k, v in cells.items() if
                         (k.startswith('$_') and 'DFF' in k) or k.startswith('FD')),
                  DSP48=cells['DSP48E1'], cells=dict(cells))
    print(label, result['LUT'], result['FF'], flush=True)
    return design, result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    baseline = OUT / 'baseline'
    baseline.mkdir(exist_ok=True)
    archive = subprocess.check_output(['git', 'archive', BASELINE, 'rtl'], cwd=ROOT)
    subprocess.run(['tar', '-x', '-C', str(baseline)], input=archive, check=True)
    resources = {}
    for source, label, post_only, xc7 in [
            (baseline, 'baseline_generic', False, False),
            (ROOT, 'candidate_generic', False, False),
            (ROOT, 'post_generic', True, False),
            (ROOT, 'post_xc7', True, True)]:
        design, resources[label] = synthesize(source, label, post_only, xc7)
        if label == 'post_generic':
            paths = analyze(design)
            (OUT / 'generic_paths.json').write_text(json.dumps(paths, indent=2) + '\n')
        if label != 'post_xc7':
            continue
        # Existing path tools reject registered DSP48E1. Its registered ports are
        # boundaries, just like the registered Pango technology wrappers.
        top = design['modules']['edrv32_npu_post']
        for cell in top['cells'].values():
            if cell['type'] == 'DSP48E1':
                cell['type'] = 'ip_mul_npu_post_dfl'
                design['modules']['ip_mul_npu_post_dfl'] = {'attributes': {'blackbox': '1'}}
        (OUT / 'mapped_boundaries.json').write_text(json.dumps(design) + '\n')
        levels = worst(design, None, None, True)
        paths = analyze(design)
        (OUT / 'levels.json').write_text(json.dumps(levels, indent=2) + '\n')
        (OUT / 'mapped_paths.json').write_text(json.dumps(paths, indent=2) + '\n')
        reset_fanout = []
        for bit in top['netnames']['rst_post_n_w']['bits']:
            polarity = [bit] + [cell['connections']['O'][0] for cell in top['cells'].values()
                                if cell['type'] == 'INV' and cell['connections']['I'] == [bit]]
            reset_fanout.append(max(sum(bits.count(net) for cell in top['cells'].values()
                                       for port, bits in cell['connections'].items()
                                       if cell['port_directions'][port] == 'input' and port != 'C')
                                   for net in polarity))
        resources[label]['reset_fanout'] = reset_fanout
        pin_loads = Counter(bit for cell in top['cells'].values()
                            for port, bits in cell['connections'].items()
                            if cell['port_directions'][port] == 'input'
                            and port.lower() not in ('c', 'clk', 'clk_i')
                            for bit in bits if isinstance(bit, int))
        resources[label]['max_nonclock_pin_fanout'] = max(pin_loads.values())
        print('native carry-chain-two:', json.dumps(levels), flush=True)
        print('regional async reset fanout:', reset_fanout, flush=True)
    merged, _ = synthesize(ROOT, 'post_merged_xc7', True, True, False)
    for cell in merged['modules']['edrv32_npu_post']['cells'].values():
        if cell['type'] == 'DSP48E1':
            cell['type'] = 'ip_mul_npu_post_dfl'
            merged['modules']['ip_mul_npu_post_dfl'] = {'attributes': {'blackbox': '1'}}
    merged_paths = analyze(merged)
    (OUT / 'merged_paths.json').write_text(json.dumps(merged_paths, indent=2) + '\n')
    print('without regional keep:', [(p['signal'], p['fanout'])
                                     for p in merged_paths['fanout'][:30]], flush=True)
    resources['delta_generic'] = {key: resources['candidate_generic'][key]
                                  - resources['baseline_generic'][key] for key in ('LUT', 'FF')}
    (OUT / 'resources.json').write_text(json.dumps(resources, indent=2) + '\n')
    (OUT / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    (OUT / 'commit.txt').write_text(subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
    print('generic NPU delta:', resources['delta_generic'])


if __name__ == '__main__':
    main()
