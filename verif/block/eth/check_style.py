#!/usr/bin/env python3
# File: check_style.py
# Spec: CLAUDE.md 7, 9.1; V-T5 SV style acceptance.
# Description: Applies repository mechanical style rules to verification SystemVerilog.
# Clock domain: none (host tool).
from pathlib import Path
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/check'))
from verilog_style import check  # noqa: E402

BASE = Path(__file__).resolve().parent
paths = sorted(BASE.rglob('*.sv')) + sorted(BASE.rglob('*.svh'))
paths.append(ROOT / 'verif/models/eth_peer_model.sv')
# Section 9.1 permits SystemVerilog and timing constructs in verification code.
rtl_only = ('forbidden syntax ', 'initial block is forbidden in RTL',
            'delay is forbidden in RTL')
errors = []
for path in paths:
    lines = path.read_text().splitlines()
    for item in check(path):
        if any(rule in item for rule in rtl_only):
            continue
        line = lines[int(item.split(':')[-2]) - 1].strip()
        if 'use named port connections' in item and line.startswith(('task ', 'function ', 'do ')):
            continue
        if 'connect one port per line' in item and not line.startswith('.'):
            continue
        errors.append(item)
for error in errors:
    print(error)
print(f'Style: {len(paths)} SV files, {len(errors)} warnings')
sys.exit(bool(errors))
