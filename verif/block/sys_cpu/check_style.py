#!/usr/bin/env python3
# File: check_style.py
# Spec: CLAUDE.md 7, 9.1; sys-subsys-plan S-I2.
# Description: Apply repository style rules to the timed SystemVerilog SC bench.
# Clock domain: none (host tool).
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.check.verilog_style import check, without_comments  # noqa: E402

out = ROOT / 'build/sys_cpu/style'
out.mkdir(parents=True, exist_ok=True)
errors = []
paths = list(Path(__file__).resolve().parent.glob('*.sv'))
for index, path in enumerate(paths):
    source = path.read_text()
    source = re.sub(r'(?m)^ *(?:task|function) automatic [^;]*;',
                    lambda match: '\n' * match[0].count('\n'), source)
    source = re.sub(r'\.(len|substr|size|pop_front)\s*\(', r'_\1(', source)
    copy = out / f'{index}.sv'
    copy.write_text(source)
    for match in re.finditer(r'\bedrv32_\w+\s+(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?'
                             r'\w+\s*\(\s*([^\s)])', without_comments(source)):
        if match[1] != '.':
            errors.append(f'{path}: module instance requires named ports')
    for error in check(copy):
        if any(allowed in error for allowed in ['forbidden syntax', 'initial block',
               'delay is forbidden', 'use named port connections']):
            continue
        errors.append(error.replace(str(copy), str(path.relative_to(ROOT))))
print('\n'.join(errors))
print(f'SC style: {len(paths)} files, {len(errors)} warnings')
sys.exit(bool(errors))
