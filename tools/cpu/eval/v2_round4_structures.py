#!/usr/bin/env python3
# File: v2_round4_structures.py; Spec: C2-I4 modeling task; Clock: host.
# RAM TAGE with saved queries and registered EX dual-load validation.
# All results are estimates; admission never consults future memory addresses.
"""Structures used by run_v2_round4.py; no RTL or technology-specific ALU mapping."""
from ipc_structures import saturate
from ooo_model import memory_width


HISTORIES = {3: (4, 16, 64), 4: (4, 12, 32, 96), 5: (4, 10, 24, 60, 144)}


def fold(value, width):
    result = 0
    while value:
        result ^= value & ((1 << width) - 1)
        value >>= width
    return result


class RamTage:
    """A 4096x2 bimodal base and 3..5 parallel tagged 1R1W RAMs.

    Longest matching provider, next matching alternate, one allocation per miss;
    3-bit direction and 2-bit usefulness; allocation pressure decrements busy
    candidates. No whole-RAM parallel aging. Histories are resolved, not speculative.
    """
    def __init__(self, count, entries):
        self.lengths = HISTORIES[count]
        self.entries = entries
        self.tables = [[None] * entries for _ in self.lengths]
        self.base = [1] * 4096
        self.history = 0
        # Include the unchanged fast gshare4096 which supplies F1 until F2.
        self.bits = 8192 + 12 + 8192 + count * entries * 16 + max(self.lengths)

    def predict(self, pc, base, index):
        keys = []
        prediction = alternate = self.base[(pc >> 2) & 4095] >= 2
        provider = -1
        width = self.entries.bit_length() - 1
        for number, length in enumerate(self.lengths):
            history = self.history & ((1 << length) - 1)
            slot = ((pc >> 2) ^ fold(history, width)) & (self.entries - 1)
            tag = ((pc >> (width + 2)) ^ fold(history, 10) ^
                   fold(history >> 1, 9)) & 1023
            keys.append((slot, tag))
            row = self.tables[number][slot]
            if row and row[0] == tag:
                alternate = prediction
                provider = number
                prediction = row[1] >= 4
        return prediction, (keys, provider, prediction, alternate)

    def update(self, pc, taken, token):
        keys, provider, prediction, alternate = token
        slot = (pc >> 2) & 4095
        self.base[slot] = saturate(self.base[slot], taken)
        if provider >= 0:
            slot, tag = keys[provider]
            row = self.tables[provider][slot]
            if row and row[0] == tag:
                row[1] = saturate(row[1], taken, 7)
                if prediction != alternate:
                    row[2] = saturate(row[2], prediction == taken)
        if prediction != taken:
            for number in range(provider + 1, len(self.tables)):
                slot, tag = keys[number]
                row = self.tables[number][slot]
                if row is None or row[2] == 0:
                    self.tables[number][slot] = [tag, 4 if taken else 3, 0]
                    break
                row[2] -= 1
        self.history = ((self.history << 1) | taken) & ((1 << max(self.lengths)) - 1)


class LoadMerge:
    """Admit independent load pairs; compare their actual addresses only in EX.

    Hit-only D$ as in round three. No MMIO merging; both accesses must fit the
    same aligned RAM read chunk. A mismatch serializes the second read with one
    full-pipeline hold cycle. Paired loads both have ordinary latency two.
    """
    def __init__(self, addresses, read_bytes):
        self.addresses = addresses
        self.read_bytes = read_bytes
        self.candidates = self.merged = self.replays = 0
        self.coverage = dict.fromkeys((8, 16, 32), 0)

    def resolve(self, records, active):
        if len(records) != 2 or any(r.instruction.kind != 'load' for r in records):
            return 0
        if any(r.trace_index < 0 for r in records):
            return 0  # Squashed speculative loads make no architectural RAM access.
        a, b = (self.addresses[r.trace_index] for r in records)
        wa, wb = (memory_width(r.instruction) for r in records)
        cacheable = all(0x10000000 <= x < 0x10010000 or 0x80000000 <= x < 0xc0000000
                        for x in (a, b))
        merged = False
        for width in self.coverage:
            same = cacheable and a // width == (a + wa - 1) // width == (
                b // width) == (b + wb - 1) // width
            self.coverage[width] += active and same
            if width == self.read_bytes:
                merged = same
        self.candidates += active
        self.merged += active and merged
        self.replays += active and not merged
        return int(not merged)
