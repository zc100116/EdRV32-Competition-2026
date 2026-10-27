#!/usr/bin/env python3
# File: synth.py
# Spec: npu-spec 5.4; CLAUDE.md 4, 8.
# Description: Measure mapped LUT6 logic between fixed registered IP boundaries.
# Clock domain: host tool; this is not physical timing or PDS resource evidence.
"""Build a generic Yosys logic-depth proxy and use tools/synth/netlist_paths.py."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/npu_datapath/synth'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'commit.txt').open('w') as commit:
        subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, stdout=commit, check=True)
    wrappers = sorted(ROOT.glob('rtl/tech/edrv32_*npu*.v'))
    # The fixed wrappers each include registered RAM/APM boundaries. Treat these as
    # sequential black boxes, matching netlist_paths.py's existing ip_* convention.
    commands = ['read_verilog -lib -D SIM_MODE -Irtl/include ' +
                ' '.join(str(p.relative_to(ROOT)) for p in wrappers),
                'read_verilog ' + ' '.join(str(p.relative_to(ROOT))
                                         for p in sorted(ROOT.glob('rtl/npu/*.v')))]
    for wrapper in wrappers:
        name = wrapper.stem
        ip = name.replace('edrv32_', 'ip_', 1)
        commands += [f'rename {name} {ip}', f'chtype -set {ip} t:{name}']
    commands += ['hierarchy -check -top edrv32_npu_datapath',
                 'synth -top edrv32_npu_datapath -flatten -noabc',
                 'abc -lut 6 -dress', 'opt_clean',
                 'write_json build/npu_datapath/synth/netlist.json', 'stat']
    script = OUT / 'synth.ys'
    script.write_text('\n'.join(commands) + '\n')
    with (OUT / 'version.txt').open('w') as version:
        subprocess.run(['yosys', '-V'], stdout=version, check=True)
    subprocess.run(['yosys', '-Q', '-T', '-l', str(OUT / 'synth.log'), '-s', str(script)],
                   cwd=ROOT, stdout=subprocess.DEVNULL, check=True)
    with (OUT / 'paths.log').open('w') as log:
        subprocess.run(['python3', 'tools/synth/netlist_paths.py',
                        str(OUT / 'netlist.json')], cwd=ROOT, stdout=log, check=True)
    print((OUT / 'paths.log').read_text())


if __name__ == '__main__':
    main()
