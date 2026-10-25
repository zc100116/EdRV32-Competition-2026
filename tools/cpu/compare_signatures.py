#!/usr/bin/env python3
# File: compare_signatures.py; cpu-testplan 2.4; clock: host.
# Compare B1 architectural result words with the Spike reference signature.
"""Compare architectural signatures: one 32-bit hexadecimal word per line, low address first."""
import argparse
from itertools import zip_longest
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', type=Path)
    parser.add_argument('reference', type=Path)
    args = parser.parse_args()
    actual = [int(word, 16) for word in args.rtl.read_text().split()]
    expected = [int(word, 16) for word in args.reference.read_text().split()]
    for index, (a, e) in enumerate(zip_longest(actual, expected)):
        if a != e:
            print(f'FAIL signature word {index}: RTL={a!r} Spike={e!r}')
            return 1
    print(f'PASS: {len(expected)} architectural signature words match')
    return 0


if __name__ == '__main__':
    sys.exit(main())
