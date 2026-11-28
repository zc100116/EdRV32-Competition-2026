#!/usr/bin/env python3
"""Capture original M5/M6 SFU inputs, preserving all underflow samples.

M5's fixture executes its original 14 variants x128 inputs, including the final
32 directed visible generic-light cases. The integer reference is checked against
M6's original small-table implementation at each captured SFU invocation.
"""
from pathlib import Path
import sys
import random

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/gpu/study'))
sys.path.insert(0, str(ROOT))
import m5_vertex as vertex
import m6_sfu as original
from tools.gpu2 import fp32 as f
from tools.gpu2 import sfu as reference


def capture(full=True):
    rows = []
    vertex_original_sfu = vertex.sfu

    def record(op, x, rsq_iterations=2):
        actual = original.sfu(op, x, rsq_iterations)
        if rsq_iterations == 2:
            code = tuple(original.LATENCY).index(op)
            word = f.bits(x)
            expected = reference.sfu(code, word)
            if expected != f.bits(actual):
                raise AssertionError((op, hex(word), hex(expected), hex(f.bits(actual))))
            rows.append((code, word, expected))
        return actual

    if not full:
        # The first 128 cases of each original M6 20000-case function stream.
        # Consume the full RNG stream so subsequent functions keep their inputs.
        rng = random.Random(20261127)
        for op in original.LATENCY:
            for sample in range(20000):
                x = vertex.fp(rng.uniform(-100, 32) if op == 'EXP2'
                              else 2 ** rng.uniform(-32, 32))
                if sample < 128:
                    record(op, x)
        return rows

    vertex.sfu = record
    vertex.study()
    # Record M6's explicit direct-function and composite pow material as well.
    original_sfu = original.sfu

    def small_record(op, x, rsq_iterations=2):
        actual = original_sfu(op, x, rsq_iterations)
        if rsq_iterations == 2:
            code = tuple(original.LATENCY).index(op)
            word = f.bits(x)
            expected = reference.sfu(code, word)
            if expected != f.bits(actual):
                raise AssertionError((op, hex(word), hex(expected), hex(f.bits(actual))))
            rows.append((code, word, expected))
        return actual

    # Preserve M6's old-M5 comparison branch and its LOG->MUL->EXP inputs;
    # the unit under test still receives the M6-small expected value for each input.
    def legacy_record(op, x, rsq_iterations=2):
        small_record(op, x, rsq_iterations)
        return vertex_original_sfu(op, x, rsq_iterations)

    vertex.sfu = legacy_record
    original.sfu = small_record
    original.study()
    original.sfu = original_sfu
    vertex.sfu = vertex_original_sfu
    return rows


if __name__ == '__main__':
    rows = capture()
    print('PASS M5/M6 integer reference', len(rows), 'original SFU invocations')
    if len(sys.argv) > 1:
        with Path(sys.argv[1]).open('w') as stream:
            stream.write(str(len(rows)) + '\n')
            for op, x, expected in rows:
                stream.write(f'{op:x} {x:08x} {expected:08x}\n')
