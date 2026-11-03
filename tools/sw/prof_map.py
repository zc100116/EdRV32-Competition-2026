#!/usr/bin/env python3
"""Map showcase PROF cache-line samples to ELF functions (design 4.5.7)."""
import argparse
import bisect
import collections
import re
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    symbols = []
    for line in subprocess.check_output(
            ["riscv-none-elf-nm", "-S", "-n", str(args.elf)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2] in "tT":
            symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
    addresses = [entry[0] for entry in symbols]
    totals = collections.Counter()
    for address, count in re.findall(r"PROF (0x[0-9a-fA-F]+) (\d+)", args.log.read_text()):
        pc = int(address, 16)
        index = bisect.bisect_right(addresses, pc) - 1
        # A sample names a 32-byte cache line; attribute to the overlapping function.
        if index < 0 or pc >= symbols[index][0] + symbols[index][1]:
            index += 1
        if index < len(symbols) and symbols[index][0] < pc + 32:
            totals[symbols[index][2]] += int(count)
    print("samples function")
    for name, count in totals.most_common():
        print(f"{count:7d} {name}")


if __name__ == "__main__":
    main()
