#!/usr/bin/env python3
# File: run.py
# Spec: sys-subsys-testplan 3.1-3.5, 5, 6; S-I1.
# Description: Build one model per scenario group and run selected SB cases serially.
#              Supply identical complete ROM/SRAM images to RTL and the reference model.
# Clock domain: none (host tool).
"""Run smoke, full (S plus F), or one numeric CASE_ID from the repository root."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files, read_test  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/sys'


def images():
    result = []
    for region, base, words in [('rom', 0, 2048), ('sram', 0x10000000, 32768)]:
        path = OUT / (region + '.hex')
        with path.open('w') as image:
            for word in range(words):
                data = 0
                for lane in range(8):
                    addr = base + word * 8 + lane
                    data |= ((addr ^ (addr >> 8) ^ (addr >> 16) ^ 0x5a) & 255) << (lane * 8)
                image.write(f'{data:016x}\n')
        result.append('+' + region.upper() + '_HEX=' + str(path))
    return result


def run(selection):
    OUT.mkdir(parents=True, exist_ok=True)
    selected = []
    for path in sorted(HERE.glob('*/test.yaml')):
        fields = read_test(path)
        if fields['top'] != 'edrv32_sys_case_tb':
            continue
        case_id = int(fields['parameters'].split('=')[1])
        if (selection == 'full' or
            selection == 'smoke' and fields['tier'] == 'smoke' or
            selection == str(case_id)):
            selected.append((case_id, path, fields))
    if not selected:
        raise ValueError(f'Unknown SB selection: {selection}')
    image_args = images()
    built = set()
    results = []
    for case_id, path, fields in sorted(selected):
        group = case_id // 100
        obj = OUT / f'group{group}/obj'
        obj.parent.mkdir(parents=True, exist_ok=True)
        if group not in built:
            args = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                    '--top-module', fields['top'], '--Mdir', str(obj), '-o', 'sim',
                    f'-GCASE_ID={group * 100 + 1}', '+define+SIM_MODE']
            args += expand_files(path.parent / fields['files'])
            with (obj.parent / 'compile.log').open('w') as log:
                subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            built.add(group)
        log_path = OUT / selection / (path.parent.name + '.log')
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open('w') as log:
            result = subprocess.run([str(obj / 'sim'), f'+CASE_ID={case_id}'] + image_args,
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=float(fields['timeout']))
        output = log_path.read_text()
        passed = result.returncode == 0 and re.search(r'\bPASS\b', output) is not None
        passed = passed and re.search(r'\bFAIL\b', output) is None
        results.append(passed)
        print(f'{"PASS" if passed else "FAIL"} {path.parent.name}: {log_path.relative_to(ROOT)}',
              flush=True)
        if not passed:
            print(output, flush=True)
    print(f'SB {selection}: {sum(results)} PASS, {len(results) - sum(results)} FAIL', flush=True)
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(run(sys.argv[1]))
