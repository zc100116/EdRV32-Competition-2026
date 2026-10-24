#!/usr/bin/env python3
"""Verify linked CPI matrix branch/target half-word placement."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys


EXPECTED = {
    "cpi_rvi_slot0_target0": (0, 0, 4),
    "cpi_rvc_slot0_target0": (0, 0, 2),
    "cpi_rvc_slot1_target0": (1, 0, 2),
    "cpi_rvi_slot1_target0": (1, 0, 4),
    "cpi_rvc_slot0_target1": (0, 1, 2),
    "cpi_rvi_slot1_target1": (1, 1, 4),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--objdump", required=True)
    parser.add_argument("--elf", required=True)
    args = parser.parse_args()

    dump = subprocess.check_output(
        [args.objdump, "-d", args.elf], text=True, encoding="utf-8"
    )
    symbol_re = re.compile(r"^\s*([0-9a-fA-F]+)\s+<([^>]+)>:", re.MULTILINE)
    symbols = {name: int(addr, 16) for addr, name in symbol_re.findall(dump)}
    insn_re = re.compile(
        r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]+)\s+([^\n]+)$", re.MULTILINE
    )
    insns = {int(addr, 16): (bits, asm) for addr, bits, asm in insn_re.findall(dump)}

    errors: list[str] = []
    for prefix, (branch_slot, target_slot, branch_bytes) in EXPECTED.items():
        branch_name = f"{prefix}_branch"
        target_name = f"{prefix}_target"
        if branch_name not in symbols or target_name not in symbols:
            errors.append(f"missing symbols for {prefix}")
            continue
        branch_addr = symbols[branch_name]
        target_addr = symbols[target_name]
        actual_branch_slot = (branch_addr >> 1) & 1
        actual_target_slot = (target_addr >> 1) & 1
        if actual_branch_slot != branch_slot:
            errors.append(
                f"{branch_name}: slot{actual_branch_slot}, expected slot{branch_slot}"
            )
        if actual_target_slot != target_slot:
            errors.append(
                f"{target_name}: slot{actual_target_slot}, expected slot{target_slot}"
            )
        if branch_addr not in insns:
            errors.append(f"{branch_name}: instruction not found in disassembly")
            continue
        bits, asm = insns[branch_addr]
        actual_bytes = len(bits) // 2
        if actual_bytes != branch_bytes:
            errors.append(
                f"{branch_name}: {actual_bytes}-byte instruction, expected {branch_bytes}"
            )
        if "bne" not in asm:
            errors.append(f"{branch_name}: expected bne/bnez, got {asm.strip()}")

    if errors:
        for error in errors:
            print(f"CPI_LAYOUT_FAIL {error}", file=sys.stderr)
        return 1

    for prefix, (branch_slot, target_slot, branch_bytes) in EXPECTED.items():
        print(
            "CPI_LAYOUT"
            f" case={prefix} branch_slot={branch_slot} target_slot={target_slot}"
            f" branch_bytes={branch_bytes}"
        )
    print("CPI_LAYOUT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
