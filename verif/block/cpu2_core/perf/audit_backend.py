#!/usr/bin/env python3
# File: audit_backend.py; cpu-v2-spec 5.2/5.3; clock: host.
"""Observe the unchanged model's ordinary-load/late-ALU issue schedule."""
import inspect
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT/'tools/cpu'))
import run_model_conformance as conformance


def main():
    simulate = conformance.simulate
    source, first = inspect.getsourcelines(simulate)
    issue_line = first + next(i for i, line in enumerate(source)
                              if line.strip() == 'issued.append(record)')

    def trace(frame, event, unused):
        if frame.f_code is simulate.__code__:
            if event == 'line' and frame.f_lineno == issue_line:
                data = frame.f_locals
                record = data['record']
                instruction = record.instruction
                if data['active']:
                    print(data['tick'], hex(instruction.pc), instruction.kind,
                          'late', record.late, 'early', record.early_load,
                          'ready', data['ready_in'])
            return trace
        return None

    sys.settrace(trace)
    try:
        conformance.model(ROOT/'build/cpu2-conformance/ordinary_load_use', 2, 0)
    finally:
        sys.settrace(None)


if __name__ == '__main__':
    main()
