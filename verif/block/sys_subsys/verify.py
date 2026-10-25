#!/usr/bin/env python3
# File: verify.py
# Spec: sys-subsys-plan S-V1 acceptance.
# Description: Compile SB configurations or build/run the stub environment selftest.
# Clock domain: none (host tool).
"""Run from the repository root after sourcing env.sh: verify.py lint|style|selftest|probes|compile."""
from pathlib import Path
import subprocess
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files, read_test  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/sys'
OUT.mkdir(parents=True, exist_ok=True)
mode = sys.argv[1]
if mode == 'lint':
    for manifest in sorted(HERE.glob('*/test.yaml')):
        fields = read_test(manifest)
        args = ['verilator', '--lint-only', '--timing', '-Wall',
                '--top-module', fields['top']]
        args += ['-G' + item for item in fields['parameters'].split()]
        args += expand_files(manifest.parent / fields['files'])
        with (OUT / (manifest.parent.name + '-lint.log')).open('w') as log:
            subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        print('PASS compile', manifest.parent.name, flush=True)
    sources = expand_files(HERE / 'binds.f') + expand_files(HERE / 'stub/bind_ports.f')
    for top in ['edrv32_bus_sys_xbar', 'edrv32_bus_apb_decoder', 'edrv32_periph_uart',
                'edrv32_periph_gpio', 'edrv32_periph_i2c', 'edrv32_periph_sysctrl']:
        with (OUT / (top + '-bind-lint.log')).open('w') as log:
            subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                            '--top-module', top] + sources, cwd=ROOT, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        print('PASS bind compile', top, flush=True)
elif mode == 'style':
    from tools.check.verilog_style import check
    paths = list(HERE.rglob('*.sv')) + list(HERE.rglob('*.svh'))
    paths += [ROOT / 'verif/models/uart_model.sv', ROOT / 'verif/models/sccb_model.sv']
    paths += [ROOT / 'verif/common' / name for name in [
        'edrv32_axi64_checker.sv', 'edrv32_axi64_master.sv', 'edrv32_axi64_observer.sv',
        'edrv32_apb_if.sv', 'edrv32_apb_checker.sv', 'edrv32_apb_memory.sv',
        'edrv32_apb_observer.sv', 'edrv32_apb_observation_pkg.sv']]
    style_dir = OUT / 'style'
    style_dir.mkdir(exist_ok=True)
    errors = []
    for index, path in enumerate(paths):
        source = path.read_text()
        # The repository's RTL scanner misidentifies ANSI task/function headers as instances.
        source = re.sub(r'(?m)^ *(?:task|function) automatic [^;]*;',
                        lambda match: '\n' * match[0].count('\n'), source)
        copy = style_dir / (str(index) + '.sv')
        copy.write_text(source)
        pattern = (r'\b(?:edrv32_\w+|uart_model|sccb_model)\s+'
                   r'(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?'
                   r'\w+\s*\(\s*([^\s)])')
        for match in re.finditer(pattern, source):
            if match[1] != '.':
                errors.append(f'{path}: module instance requires named ports')
        for error in check(copy):
            if any(allowed in error for allowed in [
                    'forbidden syntax', 'initial block', 'delay is forbidden',
                    'use named port connections']):
                continue  # CLAUDE.md 9.1 explicitly permits timed SystemVerilog testbenches.
            errors.append(error.replace(str(copy), str(path.relative_to(ROOT))))
    print('\n'.join(errors))
    print(f'SB style: {len(paths)} files, {len(errors)} warnings')
    if errors:
        raise SystemExit(1)
elif mode == 'selftest':
    fields = read_test(HERE / 'selftest/test.yaml')
    obj = OUT / 'selftest/obj'
    obj.parent.mkdir(parents=True, exist_ok=True)
    args = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
            '--top-module', fields['top'], '--Mdir', str(obj), '-o', 'sim']
    args += expand_files(HERE / 'selftest/files.f')
    with (obj.parent / 'compile.log').open('w') as log:
        subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    images = []
    for region, base, words in [('rom', 0, 2048), ('sram', 0x10000000, 32768)]:
        path = OUT / (region + '.hex')
        with path.open('w') as image:
            for word in range(words):
                data = 0
                for lane in range(8):
                    addr = base + word * 8 + lane
                    data |= ((addr ^ (addr >> 8) ^ (addr >> 16) ^ 0x5a) & 255) << (lane*8)
                image.write(f'{data:016x}\n')
        images.append('+' + region.upper() + '_HEX=' + str(path))
    with (obj.parent / 'run.log').open('w') as log:
        subprocess.run([str(obj / 'sim')] + images, cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    print('PASS selftest')
elif mode == 'compile':
    for group in ('xb', 'mem', 'ab', 'cl', 'pl', 'ua', 'gp', 'ic', 'sy'):
        fields = read_test(HERE / (group + '_01/test.yaml'))
        obj = OUT / group / 'obj'
        obj.parent.mkdir(exist_ok=True)
        args = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                '--top-module', fields['top'], '--Mdir', str(obj), '-o', 'sim']
        args += ['-G' + item for item in fields['parameters'].split()]
        args += expand_files(HERE / (group + '_01/files.f'))
        with (obj.parent / 'compile.log').open('w') as log:
            subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        print('PASS binary compile', group, flush=True)
elif mode == 'probes':
    obj = OUT / 'protocol/obj'
    obj.parent.mkdir(parents=True, exist_ok=True)
    args = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
            '--top-module', 'edrv32_sys_protocol_tb', '--Mdir', str(obj), '-o', 'sim']
    args += expand_files(HERE / 'protocol/files.f')
    with (obj.parent / 'compile.log').open('w') as log:
        subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    for flag, diagnostic in [('', 'PASS protocol'), ('BAD_AXI', 'AR payload hold'),
                             ('BAD_APB', 'APB wait hold'),
                             ('BAD_EARLY_B', 'BVALID after W'), ('BAD_APB_HOT', 'not one-hot'),
                             ('BAD_SCCB', 'SCCB START hold')]:
        name = flag.lower() if flag else 'positive'
        result = subprocess.run([str(obj / 'sim')] + (['+' + flag] if flag else []),
                                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True)
        (obj.parent / (name + '.log')).write_text(result.stdout)
        assert (result.returncode != 0) == bool(flag), (flag, result.returncode)
        assert diagnostic in result.stdout, (flag, result.stdout)
        print('PASS checker probe', name)
else:
    raise ValueError(mode)
