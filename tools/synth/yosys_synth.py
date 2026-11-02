#!/usr/bin/env python3
# File: yosys_synth.py
# Spec: C-Y1; CLAUDE.md 12.
# Description: Serial LUT6 and XC7-proxy synthesis using repository filelists.
# Clock domain: host tool.
"""Synthesize one C-Y1 target; run after sourcing the OSS CAD Suite environment."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    'edrv32_cpu_core': ['cpu.f'],
    'edrv32_cpu_subsys': ['cpu_subsys.f'],
    'edrv32_sys_subsys': ['sys_subsys.f'],
    'edrv32_fpga_cpu_sys_top': ['cpu_subsys.f', 'sys_subsys.f'],
}


def read_filelist(path, files, includes):
    for raw in path.read_text().splitlines():
        line = raw.split('//')[0].strip()
        if not line:
            continue
        if line.startswith('-f '):
            read_filelist(path.parent / line[3:], files, includes)
        elif line.startswith('+incdir+'):
            includes.add((path.parent / line[8:]).resolve().relative_to(ROOT).as_posix())
        else:
            files.append((path.parent / line).resolve().relative_to(ROOT).as_posix())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('top', choices=TARGETS)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--xc7', action='store_true', help='LUT6/CARRY4/MUX FPGA proxy')
    mode.add_argument('--hierarchical', action='store_true',
                      help='retain module boundaries for a separate resource measurement')
    args = parser.parse_args()
    output = ROOT / 'build/synth' / args.top
    output.mkdir(parents=True, exist_ok=True)
    files, includes = [], set()
    for name in TARGETS[args.top]:
        read_filelist(ROOT / 'rtl/filelists' / name, files, includes)
    if args.top == 'edrv32_fpga_cpu_sys_top':
        files.append('fpga/rtl/edrv32_fpga_cpu_sys_top.v')
    files.append('tools/synth/ip_stubs.v')
    top = args.top
    if args.top != 'edrv32_sys_subsys':
        source = next(ROOT / name for name in files if Path(name).stem == args.top)
        header = source.read_text().split(');', 1)[0]
        ports = header.split('(', 1)[1]
        names = re.findall(r'(?:input|output)\s+wire\s+(?:\[[^]]+\]\s*)?(\w+)', ports)
        top += '_measure'
        wrapper = output / 'wrapper.v'
        wrapper.write_text(f'module {top} (\n' + ports + '\n);\n' +
                           f'{args.top} u_target (\n' +
                           ',\n'.join(f'    .{name}({name})' for name in names) +
                           '\n);\nendmodule\n')
        files.append(wrapper.relative_to(ROOT).as_posix())
    read = 'read_verilog -D FPGA_MODE ' + ' '.join('-I' + p for p in sorted(includes))
    commands = [read + ' ' + ' '.join(dict.fromkeys(files))]
    relative = output.relative_to(ROOT).as_posix()
    stem = 'xc7' if args.xc7 else ('hierarchy' if args.hierarchical else 'netlist')
    flatten = '' if args.hierarchical else ' -flatten'
    commands.append(f'hierarchy -top {top}')
    if args.xc7:
        commands.append(f'synth_xilinx -top {top} -family xc7 -flatten -noiopad -noclkbuf -nobram')
    else:
        commands += [f'synth -top {top}{flatten} -noabc', 'abc -lut 6 -dress']
    commands += [
        'opt_clean',
        f'write_json {relative}/{stem}.json',
        'stat',
    ]
    script = output / f'{stem}.ys'
    script.write_text('\n'.join(commands) + '\n')
    version = subprocess.check_output(['yosys', '-V'], text=True).strip()
    (output / 'version.txt').write_text(version + '\n')
    (output / 'commit.txt').write_text(subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
    subprocess.run(['yosys', '-Q', '-T', '-l', str(output / f'{stem}.log'),
                    '-s', str(script)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    print(f'{args.top}: {output.relative_to(ROOT)}/{stem}.json', flush=True)


if __name__ == '__main__':
    main()
