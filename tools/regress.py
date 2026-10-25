#!/usr/bin/env python3
# File: regress.py
# Spec: CLAUDE.md 9.1; infra-plan I-03
# Description: Compile and run tiered self-checking HDL tests.
#              Preserve simulator exit codes and PASS/FAIL evidence in build/.
# Clock domain: none (host tool).
"""Run the smoke, full or perf tier described by verif/**/test.yaml."""
import argparse
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def read_test(path):
    fields = {}
    for line in path.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if line:
            key, value = line.split(':', 1)
            fields[key.strip()] = value.strip()
    return fields


def expand_files(path):
    result = []
    tokens = shlex.split(path.read_text(), comments=True)
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token == '-f':
            index += 1
            result.extend(expand_files(path.parent / tokens[index]))
        elif token.startswith('+incdir+'):
            result.append('+incdir+' + '+'.join(
                str((path.parent / item).resolve()) for item in token[8:].split('+')))
        elif token.startswith('+'):
            result.append(token)
        else:
            result.append(str((path.parent / token).resolve()))
        index += 1
    return result


def command(args, log, timeout):
    with log.open('w') as output:
        try:
            return subprocess.run(args, cwd=ROOT, stdout=output,
                                  stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            output.write(f'\nFAIL: timeout after {timeout} seconds\n')
            return 1


def run_test(path, fields, simulator, tier):
    name = path.parent.relative_to(ROOT / 'verif')
    out = ROOT / 'build/regress' / tier / name / simulator
    out.mkdir(parents=True, exist_ok=True)
    top = fields['top']
    sources = expand_files(path.parent / fields['files'])
    defines = ['+define+' + item for item in shlex.split(fields['defines'])]
    parameters = shlex.split(fields['parameters'])
    timeout = float(fields['timeout'])
    if fields['software']:
        subprocess.run(['make', '-C', str(ROOT / 'sw'),
                        'PROGRAM=' + fields['software']], check=True)
    if simulator == 'verilator':
        compile_args = ['verilator', '--binary', '--timing', '--top-module', top,
                        '--Mdir', str(out / 'obj'), '-o', 'sim']
        compile_args += ['-G' + item for item in parameters]
        run_args = [str(out / 'obj/sim')]
    elif simulator == 'iverilog':
        compile_args = ['iverilog', '-g2012', '-s', top, '-o', str(out / 'sim')]
        compile_args += ['-P' + top + '.' + item for item in parameters]
        run_args = ['vvp', str(out / 'sim')]
    else:
        raise ValueError(f'{path}: unknown simulator {simulator}')
    if fields['software']:
        image = ROOT / 'build/sw' / fields['software']
        run_args += [f'+{region.upper()}_HEX={image / (region + ".hex")}'
                     for region in ('rom', 'sram', 'ddr')]
    result = command(compile_args + defines + sources, out / 'compile.log', timeout)
    if result == 0:
        result = command(run_args, out / 'run.log', timeout)
        output = (out / 'run.log').read_text()
        passed = (result == 0 and re.search(r'\b' + re.escape(fields['pass']) + r'\b', output)
                  and not re.search(r'\bFAIL\b', output))
    else:
        passed = False
    print(f'{"PASS" if passed else "FAIL"} {name} [{simulator}] ({out.relative_to(ROOT)})')
    return bool(passed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', choices=('smoke', 'full', 'perf'))
    args = parser.parse_args()
    results = []
    for path in sorted((ROOT / 'verif').rglob('test.yaml')):
        fields = read_test(path)
        tiers = shlex.split(fields['tier'])
        if args.tier in tiers or (args.tier == 'full' and 'smoke' in tiers):
            for simulator in shlex.split(fields['simulator']):
                results.append(run_test(path, fields, simulator, args.tier))
    print(f'Summary: {sum(results)} PASS, {len(results) - sum(results)} FAIL')
    return 0 if results and all(results) else 1


if __name__ == '__main__':
    sys.exit(main())
