#!/usr/bin/env python3
# File: pipe_model.py; Spec: cpu-spec 2.3, 4.1-4.4, 7.1; Clock: host.
# Replay Spike commits through a hit-only, cycle-stepped frontend and dual-issue backend.
# Retain speculative fetch and F1 predictor indices; train surviving instructions in E.
"""Cycle approximation, with HPM windows defined by retired start_time/stop_time PCs."""
import argparse
from collections import deque
from dataclasses import dataclass, replace
import json
from pathlib import Path
import subprocess

from analyze import COMMIT, CONTROL, DISASM, decode

VARIANTS = ('V0', 'V1', 'V2', 'V3', 'V4a', 'V3+V4a', 'V4b', 'V3+V4b', 'V5', 'V3+V5')


@dataclass
class Record:
    instruction: object
    hit: bool
    taken: bool
    target: int
    index: int
    checkpoint: tuple
    next_pc: int = 0
    d_redirect: bool = False


class Predictor:
    """C-E2 grouped BTB/gshare/RAS algorithm, scheduled at F1 and E like the RTL."""

    def __init__(self, btb_size, pht_size, group_bytes):
        self.btb = [None] * btb_size
        self.pht = [1] * pht_size
        self.history = 0
        self.shift = group_bytes.bit_length() - 1
        self.stack = [0] * 4
        self.pointer = 0
        self.count = 0

    def snapshot(self):
        return self.pointer, self.count, self.stack[(self.pointer - 1) % 4]

    def action(self, instruction):
        if instruction.pop and self.count:
            self.pointer = (self.pointer - 1) % 4
            self.count -= 1
        if instruction.push:
            self.stack[self.pointer] = instruction.pc + instruction.size
            self.pointer = (self.pointer + 1) % 4
            self.count = min(4, self.count + 1)

    def restore(self, record):
        self.pointer, self.count, top = record.checkpoint
        if self.count:
            self.stack[(self.pointer - 1) % 4] = top
        self.action(record.instruction)

    def query(self, pc):
        entry = self.btb[(pc >> self.shift) & (len(self.btb) - 1)]
        if entry and (entry[0].pc >> self.shift != pc >> self.shift or entry[0].pc < pc):
            entry = None
        taken = False
        target = 0
        if entry:
            instruction, target = entry
            index = ((instruction.pc >> 1) ^ self.history) & (len(self.pht) - 1)
            taken = instruction.kind != 'branch' or self.pht[index] >= 2
            if instruction.pop and self.count:
                target = self.stack[(self.pointer - 1) % 4]
        return entry, taken, target, self.history, self.snapshot()

    def update(self, record):
        instruction = record.instruction
        if instruction.kind not in CONTROL:
            return
        taken = record.next_pc != instruction.pc + instruction.size
        target = record.next_pc if instruction.kind == 'jalr' else instruction.target
        self.btb[(instruction.pc >> self.shift) & (len(self.btb) - 1)] = instruction, target
        if instruction.kind == 'branch':
            delta = 1 if taken else -1
            self.pht[record.index] = min(3, max(0, self.pht[record.index] + delta))
            self.history = ((self.history << 1) | taken) & (len(self.pht) - 1)


def program_and_trace(out):
    # -z decodes alignment zeros too: speculative fall-through can enter that padding.
    disasm = subprocess.check_output(
        ['riscv-none-elf-objdump', '-d', '-z', '-M', 'no-aliases,numeric',
         str(out / 'coremark.elf')], text=True)
    (out / 'numeric.dis').write_text(disasm)
    program = {}
    for line in disasm.splitlines():
        if match := DISASM.match(line):
            pc, bits = int(match[1], 16), int(match[2], 16)
            instruction = decode(pc, bits, match[3], match[4])
            if match[3] in {'unimp', 'c.unimp'}:
                instruction = replace(instruction, kind='illegal')
            program[pc] = instruction
    names = subprocess.check_output(['riscv-none-elf-nm', str(out / 'coremark.elf')], text=True)
    symbols = {parts[2]: int(parts[0], 16) for line in names.splitlines()
               if len(parts := line.split()) == 3}
    for pc, instruction in program.items():
        kind = instruction.kind
        if kind == 'muldiv':
            kind = 'div' if (instruction.bits >> 12) & 4 else 'mul'
        if kind == 'serial' and instruction.bits & 0x7f == 0x73:
            if (instruction.bits >> 12) & 7:
                kind = 'csr'
                bits = instruction.bits
                sources = () if bits & 0x4000 else ((bits >> 15) & 31,)
                instruction = replace(instruction, rd=(bits >> 7) & 31, sources=sources)
        program[pc] = replace(instruction, kind=kind)
    trace = []
    # Keep the prefix: predictor state at start_time is warm, as in the B2 run.
    with (out / 'spike.log').open() as log:
        for line in log:
            match = COMMIT.match(line)
            if match:
                pc = int(match[1], 16)
                trace.append(pc)
                if pc == symbols['stop_time']:
                    break
    return program, symbols, trace


def simulate(program, trace, begin, end, variant='V0'):
    swap = variant in {'V1', 'V3', 'V3+V4a', 'V3+V4b', 'V3+V5'}
    branch_lane = variant in {'V2', 'V3', 'V3+V4a', 'V3+V4b', 'V3+V5'}
    dual_query = variant in {'V4b', 'V3+V4b'}
    group_bytes = 16 if variant in {'V4a', 'V3+V4a', 'V4b', 'V3+V4b'} else 8
    depth = 8 if group_bytes == 16 else 4
    btb, pht = (64, 1024) if variant in {'V5', 'V3+V5'} else (32, 512)
    predictor = Predictor(btb, pht, 8 if dual_query else group_bytes)
    ib = deque()
    halfwords = []
    pending = []
    fetch_pc = trace[0]
    cross_target = None
    e, m, w = [], [], []
    cursor = 0
    active = False
    cycles = 0
    counters = [0] * 17
    division_left = 0

    def hazard(instruction):
        waits = []
        for source in instruction.sources:
            if source == 0:
                continue
            for stage, records in ((0, e), (1, m)):
                producer = next((r.instruction for r in reversed(records)
                                 if r.instruction.rd == source and source), None)
                if producer:
                    if producer.kind == 'mul' or (stage == 0 and producer.kind in {'load', 'csr'}):
                        waits.append(producer.kind)
                    break
        return waits

    while True:
        if any(r.instruction.pc == end for r in w):
            break
        if any(r.instruction.pc == begin for r in w):
            active = True
        events = [0] * 17
        events[1 if len(w) == 2 else 2 if w else 3] = 1
        events[4] = sum(r.instruction.kind in CONTROL for r in w)

        # E resolves before D can issue. A wrong younger member is squashed here.
        redirect = None
        surviving = []
        for record in e:
            instruction = record.instruction
            actual_taken = (instruction.kind in {'jal', 'jalr'} or
                            (instruction.kind == 'branch' and
                             record.next_pc != instruction.pc + instruction.size))
            wrong = (record.taken != actual_taken or
                     (record.taken and record.target != record.next_pc))
            surviving.append(record)
            if wrong and not record.d_redirect:
                redirect = record
                break
        div_wait = bool(division_left and any(r.instruction.kind == 'div' for r in e))
        events[10] = int(div_wait)
        if div_wait:
            division_left -= 1
            redirect = None
        events[16] = int(redirect is not None)
        available = not redirect and not div_wait
        events[12] = int(not ib and available)
        if ib and e:
            inst = ib[0].instruction
            events[9] = int(any(r.instruction.kind == 'load' and r.instruction.rd and
                               r.instruction.rd in inst.sources for r in e))

        issued = []
        d_redirect = None
        if ib and available and cursor < len(trace):
            older = ib[0].instruction
            if not hazard(older) and not (older.kind == 'csr' and (e or m)):
                count = 1
                reason = 8
                if len(ib) >= 2:
                    younger = ib[1].instruction
                    raw = older.rd and older.rd in younger.sources
                    structural = older.kind in {'csr', 'serial'} or hazard(younger)
                    supported = (younger.kind == 'alu' or
                                 (branch_lane and younger.kind in {'branch', 'jal'}))
                    exchanged = swap and older.kind == 'alu' and not supported
                    exchanged = exchanged and younger.kind not in {'csr', 'serial', 'illegal'}
                    reason = 5 if raw else 6 if structural else 7 if not (
                        supported or exchanged) else 0
                    if not reason:
                        count = 2
                if older.kind == 'jal' and not ib[0].hit:
                    count = 1
                    d_redirect = ib[0]
                    d_redirect.d_redirect = True
                    events[16] = 1
                elif count == 2 and ib[1].instruction.kind == 'jal' and not ib[1].hit:
                    d_redirect = ib[1]
                    d_redirect.d_redirect = True
                    events[16] = 1
                if count == 1 and reason:
                    events[reason] = 1
                for slot in range(count):
                    record = ib.popleft()
                    instruction = record.instruction
                    record.next_pc = trace[cursor + 1] if cursor + 1 < len(trace) else end + 4
                    if cursor < len(trace) and instruction.pc == trace[cursor]:
                        cursor += 1
                    else:
                        if slot == 0:
                            raise ValueError(f'trace mismatch at commit {cursor}: '
                                             f'fetch PC {instruction.pc:08x}, '
                                             f'Spike PC {trace[cursor]:08x}')
                        # Only a younger member of an unresolved taken branch can be wrong-path.
                        record.next_pc = instruction.pc + instruction.size
                    issued.append(record)
                if any(r.instruction.kind == 'div' for r in issued):
                    division_left = 33

        # F2 can append the arriving hit and drain two instructions into IB in the same cycle.
        flush = redirect or d_redirect
        query = None
        if not flush:
            halfwords.extend(pending)
            pending = []
            for _ in range(min(2, depth - len(ib))):
                if not halfwords:
                    break
                pc, meta = halfwords[0]
                instruction = program[pc]
                length = instruction.size // 2
                if len(halfwords) < length:
                    break
                entry, taken, target, history, checkpoint = meta
                hit = bool(entry and entry[0].pc == pc)
                record = Record(instruction, hit, hit and taken, target,
                                ((pc >> 1) ^ history) & (pht - 1), checkpoint)
                ib.append(record)
                del halfwords[:length]
            if len(halfwords) <= group_bytes // 2:
                query = predictor.query(fetch_pc)
                first_query = query
                second_query = None
                midpoint = (fetch_pc & -group_bytes) + 8
                if dual_query and fetch_pc < midpoint and cross_target is None:
                    second_query = predictor.query(midpoint)
                    if not query[1] and second_query[1]:
                        query = second_query
                entry, taken, target, history, checkpoint = query
                group_end = (fetch_pc & -group_bytes) + group_bytes
                request_end = group_end
                if cross_target is not None:
                    # The tail request of a split control has no independent BTB/RAS action.
                    query = (None, False, 0, history, checkpoint)
                    request_end = fetch_pc + 2
                    next_fetch = cross_target
                    cross_target = None
                elif taken:
                    branch_end = entry[0].pc + entry[0].size
                    request_end = min(group_end, branch_end)
                    if branch_end > group_end:
                        next_fetch = group_end
                        cross_target = target
                    else:
                        next_fetch = target
                else:
                    next_fetch = group_end
                if dual_query and second_query:
                    pending = [(pc, first_query if pc < midpoint else second_query)
                               for pc in range(fetch_pc, request_end, 2)]
                else:
                    pending = [(pc, query) for pc in range(fetch_pc, request_end, 2)]
                fetch_pc = next_fetch

        # All predictor mutations occur at the edge, after the concurrent F1 query.
        if not div_wait:
            for record in surviving:
                predictor.update(record)
        if flush:
            predictor.restore(flush)
            fetch_pc = flush.next_pc
            ib.clear()
            halfwords = []
            pending = []
            cross_target = None
        elif query and query[1]:
            predictor.action(query[0][0])
        if div_wait:
            w, m = m, []
        else:
            w, m, e = m, surviving, issued
        if active:
            cycles += 1
            for event, count in enumerate(events):
                if count:
                    counters[event] += count
    result = dict(cycles=cycles, instructions=2 * counters[1] + counters[2],
                  **{f'hpm{i}': counters[i] for i in range(1, 17)})
    result['ipc'] = result['instructions'] / result['cycles']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='directory with coremark.elf and spike.log')
    parser.add_argument('--variant', choices=VARIANTS, default='V0')
    args = parser.parse_args()
    program, symbols, trace = program_and_trace(args.directory)
    print(json.dumps(simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                              args.variant), indent=2))


if __name__ == '__main__':
    main()
