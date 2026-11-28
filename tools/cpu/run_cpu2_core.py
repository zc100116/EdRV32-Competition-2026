#!/usr/bin/env python3
# File: run_cpu2_core.py; Spec: cpu-v2-testplan CV01/CV06/CV15; Clock: host.
"""Build one fixed CPU2 configuration and run its software smoke manifest."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--width', type=int, choices=[1, 2], required=True)
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--program')
    args = parser.parse_args()
    out = ROOT / 'build/cpu2_core' / f'w{args.width}'
    out.mkdir(parents=True, exist_ok=True)
    sim = out / 'Vtb'
    if not args.no_build:
        cmd = ['verilator', '--binary', '--timing', '-Wall', '-DSIM_MODE', '-j', '4',
               '--top-module', 'tb', f'-GISSUE_WIDTH={args.width}', '-f', 'files.f',
               '--Mdir', str(out)]
        with (out / 'compile.log').open('w') as log:
            subprocess.run(cmd, cwd=ROOT / 'verif/block/cpu2_core', stdout=log,
                           stderr=subprocess.STDOUT, check=True)
    manifest = 'coremark.json' if args.program == 'coremark' else 'programs.json'
    programs = json.loads((ROOT / 'build/cpu2_core/programs' / manifest).read_text())
    selected = [next(p for p in programs if p['name'] == args.program)] if args.program else programs
    for program in selected:
        command = [str(sim), '+MEM_HEX=' + str(ROOT / program['image']),
                   '+TOHOST_ADDR=' + program['tohost'], '+MAX_CYCLES=20000000']
        if 'begin' in program:
            command += ['+PERF_BEGIN=' + program['begin'], '+PERF_END=' + program['end']]
        log = out / (program['name'] + '.log')
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        log.write_text(result.stdout)
        print(program['name'], result.stdout.splitlines()[0], flush=True)
        if result.returncode:
            raise RuntimeError(f'{program["name"]} failed: {log}')
        if 'iterations' in program:
            import re
            cycles = int(re.search(r'PERF width=\d+ cycles=(\d+)', result.stdout)[1])
            print(f'CoreMark/MHz={program["iterations"] * 1000000 / cycles:.6f}', flush=True)
            if re.search(r'ERROR! (list|matrix|state) crc', result.stdout):
                raise RuntimeError('CoreMark CRC mismatch: ' + str(log))
    print(f'PASS width={args.width}: {len(selected)} programs')


if __name__ == '__main__':
    main()
