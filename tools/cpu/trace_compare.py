#!/usr/bin/env python3
# File: trace_compare.py; cpu-spec 3.4; cpu-testplan 2.3; clock: host.
# Compare ordered retirements and mcause trap events, stopping at the first mismatch.
"""RTL format (hexadecimal, one event per line): PC instr rd value, or trap mcause.
No writeback: rd=value=0. C instructions retain their original 16-bit encoding.
The producer emits pipeline 0 before pipeline 1 on a dual-retirement cycle, then
any trap event. Trap entry is an event, not a retired instruction. Spike input
must include -l --log-commits so synchronous traps are visible. A raw faulting
instruction disassembly is not a retirement. No CSR or memory side effects are
compared, because cpu-spec 3.4 exposes only GPR writeback and mcause.
"""
import argparse
from dataclasses import dataclass
from itertools import zip_longest
from pathlib import Path
import re
import sys

COMMIT = re.compile(r'^core\s+\d+:\s+[0-3]\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)$')
WRITE = re.compile(r'\bx\s*(\d+)\s+0x([0-9a-f]+)')
TRAP = re.compile(r'exception trap_(\w+),')
# Coordinator-approved counter waiver: cpu-spec 5 counters depend on RTL time/IPC.
# Compare PC/instruction/rd, but not the read result of these exact CSR addresses.
COUNTER_CSRS = {
    0xB00, 0xB02, *range(0xB03, 0xB0B),
    0xB80, 0xB82, *range(0xB83, 0xB8B),
    *range(0xC00, 0xC0B), *range(0xC80, 0xC8B),
}
CAUSES = {
    'instruction_address_misaligned': 0, 'instruction_access_fault': 1,
    'illegal_instruction': 2, 'breakpoint': 3, 'load_address_misaligned': 4,
    'load_access_fault': 5, 'store_address_misaligned': 6, 'store_access_fault': 7,
    'user_ecall': 8, 'supervisor_ecall': 9, 'machine_ecall': 11,
    'instruction_page_fault': 12, 'load_page_fault': 13, 'store_page_fault': 15,
}


@dataclass(frozen=True)
class Event:
    pc: int = 0
    instr: int = 0
    rd: int = 0
    value: int = 0
    cause: int | None = None

    def __str__(self):
        if self.cause is not None:
            return f'trap {self.cause:08x}'
        return f'{self.pc:08x} {self.instr:08x} {self.rd:02x} {self.value:08x}'


def rtl_events(path):
    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == 'trap':
            yield Event(cause=int(fields[1], 16))
        else:
            pc, instr, rd, value = (int(item, 16) for item in fields)
            yield Event(pc, instr, rd, value if rd else 0)


def spike_events(path):
    for line in path.read_text().splitlines():
        if match := COMMIT.match(line):
            write = WRITE.search(match[3])
            rd = int(write[1]) if write else 0
            value = int(write[2], 16) if rd else 0
            yield Event(int(match[1], 16), int(match[2], 16), rd, value)
        elif match := TRAP.search(line):
            yield Event(cause=CAUSES[match[1]])
        elif match := re.search(r'exception interrupt #(\d+),', line):
            yield Event(cause=0x80000000 | int(match[1]))


def compare(rtl, spike):
    for index, (actual, expected) in enumerate(zip_longest(rtl, spike), 1):
        counter_read = (expected is not None and expected.cause is None
                        and expected.instr & 0x7F == 0x73
                        and (expected.instr >> 12) & 7 != 0
                        and expected.instr >> 20 in COUNTER_CSRS)
        if counter_read and actual is not None:
            equal = (actual.pc, actual.instr, actual.rd, actual.cause) == (
                expected.pc, expected.instr, expected.rd, expected.cause)
        else:
            equal = actual == expected
        if not equal:
            print(f'FAIL event {index}\nRTL:   {actual or "<end>"}\nSpike: {expected or "<end>"}')
            return 1
    print('PASS: retirement and trap sequences match')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', type=Path)
    parser.add_argument('spike', type=Path)
    args = parser.parse_args()
    return compare(rtl_events(args.rtl), spike_events(args.spike))


if __name__ == '__main__':
    sys.exit(main())
