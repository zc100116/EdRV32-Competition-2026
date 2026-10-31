#!/usr/bin/env python3
# File: expect.py
# Spec: Task T-RNDB2; rnd-spec v0.3 2.6 integer rendering.
# Description: Compute reference CRCs and compare a captured UART log.
# Clock domain: host.
import argparse
from pathlib import Path
import re
import sys
import zlib

sys.dont_write_bytecode = True
from scenes import ARENA_BYTES, BASES, DATA, GROUPS, SIZES, blob, ref


def expected():
    memory = bytearray(ARENA_BYTES)
    memory[DATA:DATA + len(blob)] = blob
    values = {}
    for name, fmt, commands in GROUPS:
        result = ref.execute(memory, commands)
        if result.error:
            raise RuntimeError(f'{name}: reference ERR_CODE={result.error}')
        values[name] = zlib.crc32(memory[BASES[fmt]:BASES[fmt] + SIZES[fmt]])
    return values


def compare(log, values):
    seen = set()
    passed = True
    for line in log.splitlines():
        match = re.fullmatch(r'RND (\w+) crc=0x([0-9a-fA-F]{8})', line)
        if match:
            name, actual = match[1], int(match[2], 16)
            if name not in values:
                print(f'FAIL unexpected group {name}')
                passed = False
                continue
            seen.add(name)
            want = values[name]
            ok = actual == want
            print(f'{"PASS" if ok else "FAIL"} {name} actual=0x{actual:08x} '
                  f'expected=0x{want:08x}')
            passed &= ok
        error = re.fullmatch(r'RND ERR_CODE=0x([0-9a-fA-F]{8}) CUR_DESC=0x[0-9a-fA-F]{8}', line)
        if error and int(error[1], 16):
            print(f'FAIL {line}')
            passed = False
    for name in values.keys() - seen:
        print(f'FAIL missing {name}')
        passed = False
    print('PASS' if passed else 'FAIL')
    return passed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', nargs='?', type=Path, help='UART log to compare')
    args = parser.parse_args()
    values = expected()
    if args.log:
        sys.exit(0 if compare(args.log.read_text(), values) else 1)
    for name, crc in values.items():
        print(f'RND {name} crc=0x{crc:08x}')
