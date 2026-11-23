#!/usr/bin/env python3
# File: gen_recip_p18.py
# Spec: gpu-spec 2.13.10.
# Description: Emit the 1024 midpoint reciprocal seeds as 18-bit HEX words.
# Clock domain: none (host).
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(''.join(f'{((1 << 28) + (2049 + 2*i)//2)//(2049 + 2*i):05x}\n'
                                  for i in range(1024)))


if __name__ == '__main__':
    main()
