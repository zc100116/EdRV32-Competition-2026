#!/usr/bin/env python3
# File: check_style.py
# Spec: CLAUDE.md 6, 7, 9.1 (SystemVerilog testbench subset).
# Description: Apply repository mechanical style rules to N-V1 verification sources.
#              The RTL-only checker rejects the SV syntax expressly allowed for tests.
# Clock domain: none (host check).
"""Check the NPU verification SV sources; language semantics are checked by Verilator."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
SOURCES = [ROOT/'verif/models/npu_axi256_mem.sv',
           ROOT/'verif/unit/npu_axi256_mem/tb_npu_axi256_mem.sv',
           ROOT/'verif/block/npu/tb_npu.sv']
SOURCES += sorted((ROOT/'verif/block/npu/post').glob('*.sv'))


def main():
    errors = []
    for path in SOURCES:
        text = path.read_text()
        header = '\n'.join(text.splitlines()[:12])
        for label in ['File:', 'Spec:', 'Description:', 'Clock']:
            if label not in header:
                errors.append(f'{path}:1: missing header {label}')
        clean = re.sub(r'/\*.*?\*/|//[^\n]*',
                       lambda match: re.sub(r'[^\n]', ' ', match[0]), text, flags=re.S)
        for n, (raw, line) in enumerate(zip(text.splitlines(), clean.splitlines()), 1):
            message = None
            if '\t' in raw:
                message = 'tab character'
            elif line.strip() and len(raw.rstrip()) > 100:
                message = 'code exceeds 100 columns'
            elif line.strip() and (len(line)-len(line.lstrip())) % 4:
                message = 'indentation is not a multiple of four'
            elif re.match(r'\s*\.\w+\s*\(', line) and len(re.findall(r'\.\w+\s*\(', line)) > 1:
                message = 'connect one port per line'
            elif re.search(r'`(?:ifdef|ifndef|elsif|else|endif)\b', line):
                message = 'conditional compilation outside rtl/tech'
            if message:
                errors.append(f'{path.relative_to(ROOT)}:{n}: {message}')
        module = re.search(r'\bmodule\s+(\w+)', clean)
        if module is None or module[1] != path.stem:
            errors.append(f'{path}: module/file name mismatch')
    for error in errors:
        print(error)
    print(f'Style: {len(SOURCES)} SV files, {len(errors)} warnings')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
