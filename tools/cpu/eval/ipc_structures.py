#!/usr/bin/env python3
# File: ipc_structures.py; Spec: T-CPU-IPC2, T-CPU-N-MODEL; Clock: host.
# Experimental macro instructions and saved-query second-level direction predictors.
"""State sizes exclude the shared BTB and RAS; no speculative direction training."""
from dataclasses import dataclass, replace


FUSIONS = ('addi-andi', 'srli-or', 'lui-addi', 'slli-add', 'add-load', 'auipc-jalr')


def operation(inst):
    bits = inst.bits
    opcode, funct = bits & 127, (bits >> 12) & 7
    if opcode == 0x37:
        return 'lui'
    if opcode == 0x17:
        return 'auipc'
    if opcode == 0x13:
        return {0: 'addi', 1: 'slli', 4: 'xori', 5: 'srli' if bits >> 30 == 0 else 'srai',
                6: 'ori', 7: 'andi'}.get(funct, 'other')
    if opcode == 0x33:
        return {0: 'add' if bits >> 25 == 0 else 'other', 1: 'sll', 4: 'xor',
                5: 'srl' if bits >> 30 == 0 else 'sra', 6: 'or', 7: 'and'}.get(funct, 'other')
    if opcode == 3 and funct in (1, 2, 4):
        return 'load'
    if inst.kind == 'jalr':
        return 'jalr'
    return 'other'


@dataclass(frozen=True)
class Macro:
    pc: int
    bits: int
    size: int
    kind: str
    rd: int
    sources: tuple
    target: int
    pop: bool
    push: bool
    members: tuple
    template: str


def fuse_program(program, trace, templates, begin, end):
    """Keep both architectural destinations, but expose one scheduling/issue unit."""
    program = dict(program)
    eligible = {}
    for pc, first in list(program.items()):
        second = program.get(pc + first.size)
        if not second or second.pc in (begin, end) or not first.rd:
            continue
        if first.rd not in second.sources:
            continue
        name = operation(first) + '-' + operation(second)
        if name not in templates:
            continue
        sources = tuple(dict.fromkeys(first.sources + tuple(
            source for source in second.sources if source != first.rd)))
        eligible[pc] = Macro(pc, second.bits, first.size + second.size, second.kind,
                             second.rd, sources, second.target, second.pop, second.push,
                             (first, second), name)
    # Greedy non-overlapping decode, also when a branch enters the second instruction.
    collapsed = []
    index = 0
    while index < len(trace):
        pc = trace[index]
        collapsed.append(pc)
        if pc in eligible and index + 1 < len(trace) and (
                trace[index + 1] == eligible[pc].members[1].pc):
            program[pc] = eligible[pc]
            index += 2
        else:
            index += 1
    return program, collapsed


def destinations(inst):
    return tuple(i.rd for i in inst.members if i.rd) if isinstance(inst, Macro) else (inst.rd,)


class SavedHistory(int):
    pass


def saturate(value, taken, maximum=3):
    return min(maximum, max(0, value + (1 if taken else -1)))


class Direction:
    """loop: 64 direct-mapped entries; tournament: local/global; TAGE: 3 tagged tables."""
    def __init__(self, kind):
        self.kind = kind
        if kind == 'loop':
            # valid, PC tag24, trip13, current12, confidence2, direction1; GHR12.
            self.bits = 8192 + 12 + 64 * 53
            self.loops = [None] * 64
        elif kind in {'tournament', 'tournament-confident'}:
            self.bits = 8192 + 12 + 256 * 10 + 1024 * 2 + 4096 * 2
            self.local_history = [0] * 256
            self.local = [1] * 1024
            self.chooser = [1] * 4096
        elif kind == 'tage':
            # base4096x2 + 3x256(valid+tag10+counter3+useful2), GHR64, aging8.
            self.bits = 8192 + 12 + 3 * 256 * 16 + 64 + 8
            self.tables = [[None] * 256 for _ in range(3)]
            self.lengths = (4, 16, 64)
            self.history = 0
            self.clock = 0

    def predict(self, pc, global_prediction, index):
        if self.kind == 'loop':
            slot = (pc >> 2) & 63
            row = self.loops[slot]
            prediction = global_prediction
            if row and row[0] == pc >> 8 and row[3] == 3 and row[1]:
                prediction = row[4] if row[2] + 1 < row[1] else not row[4]
            return prediction, (slot,)
        if self.kind in {'tournament', 'tournament-confident'}:
            slot = (pc >> 2) & 255
            local_index = self.local_history[slot]
            local = self.local[local_index] >= 2
            use_local = self.chooser[index] >= 2
            if self.kind == 'tournament-confident':
                use_local = self.chooser[index] == 3 and self.local[local_index] in (0, 3)
            prediction = local if use_local else global_prediction
            return prediction, (slot, local_index, index, local, global_prediction)
        keys = []
        prediction = global_prediction
        provider = -1
        alternate = global_prediction
        for number, length in enumerate(self.lengths):
            history = self.history & ((1 << length) - 1)
            folded = history ^ (history >> 9) ^ (history >> 18) ^ (history >> 36)
            slot = ((pc >> 2) ^ folded) & 255
            tag = ((pc >> 11) ^ history ^ (history >> 10) ^ (history >> 30)) & 1023
            keys.append((slot, tag))
            row = self.tables[number][slot]
            if row and row[0] == tag:
                alternate = prediction
                provider = number
                prediction = row[1] >= 4
        return prediction, (keys, provider, prediction, alternate)

    def update(self, pc, taken, token):
        if self.kind == 'loop':
            slot, = token
            row = self.loops[slot]
            tag = pc >> 8
            if not row or row[0] != tag:
                self.loops[slot] = [tag, 0, 1, 0, taken]
            elif taken == row[4]:
                row[2] = (row[2] + 1) & 4095
            else:
                trip = row[2] + 1
                row[3] = min(3, row[3] + 1) if trip == row[1] else 0
                row[1], row[2] = trip, 0
            return
        if self.kind in {'tournament', 'tournament-confident'}:
            slot, local_index, index, local, glob = token
            if local != glob:
                self.chooser[index] = saturate(self.chooser[index], local == taken)
            self.local[local_index] = saturate(self.local[local_index], taken)
            self.local_history[slot] = ((self.local_history[slot] << 1) | taken) & 1023
            return
        keys, provider, prediction, alternate = token
        if provider >= 0:
            slot, tag = keys[provider]
            row = self.tables[provider][slot]
            if row and row[0] == tag:
                row[1] = saturate(row[1], taken, 7)
                if prediction != alternate:
                    row[2] = saturate(row[2], prediction == taken)
        if prediction != taken:
            for number in range(provider + 1, 3):
                slot, tag = keys[number]
                row = self.tables[number][slot]
                if row is None or row[2] == 0:
                    self.tables[number][slot] = [tag, 4 if taken else 3, 0]
                    break
                row[2] -= 1
        self.history = ((self.history << 1) | taken) & ((1 << 64) - 1)
        self.clock += 1
        if self.clock % 256 == 0:
            for table in self.tables:
                for row in table:
                    if row:
                        row[2] >>= 1
