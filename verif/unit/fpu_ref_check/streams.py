#!/usr/bin/env python3
# File: streams.py
# Spec: fpu-testplan FT01; coordinator F05 sampling clarification.
# Description: Exercise a complete level2 unary stream and ten sampled seeds.
# Clock: host only.
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools/fpu'))
from generate import full_rows, tf_rows
from reference import Reference


def check_streams():
    reference = Reference()
    total = 0
    for rm in range(5):
        rows = list(full_rows('to_w', 32, 32, rm))
        assert len(rows) == 8800
        for row in rows:
            actual = reference.evaluate('to_w', 32, 32, *row[:4], rm)
            assert actual == (row[4] & 0xffffffff, row[5], 1), (rm, row, actual)
        total += len(rows)
    for seed in range(10):
        count = 0
        for row in tf_rows('to_w', 32, 32, 0, seed, 10000, 2):
            actual = reference.evaluate('to_w', 32, 32, *row[:4], 0)
            assert actual == (row[4] & 0xffffffff, row[5], 1), (seed, row, actual)
            count += 1
        assert count == 10000
        total += count
    print(f'PASS {total} level2 unary and ten-seed sampled reference checks')


if __name__ == '__main__':
    check_streams()
