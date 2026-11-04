#!/usr/bin/env python3
# File: pipe_model.py; Spec: cpu-spec 2.3, 4.1-4.4, 7.1; Clock: host.
# Replay Spike commits through a hit-only, cycle-stepped frontend and dual-issue backend.
# Retain speculative fetch/F1 indices; train surviving E/M controls under C-E7 late execution.
"""Cycle approximation, with HPM windows defined by retired start_time/stop_time PCs."""
import argparse
from collections import deque
from dataclasses import dataclass, replace
import json
from pathlib import Path
import subprocess

from analyze import COMMIT, CONTROL, DISASM, decode

VARIANTS = ('V0', 'V1', 'V2', 'V2s', 'V2s+V5', 'V3', 'V3s', 'V4a', 'V3+V4a',
            'V4b', 'V3+V4b', 'V5', 'V3+V5',
            'L1', 'L1+V5', 'L2', 'L2+V5', 'L2b', 'L2b+V5', 'L2s', 'L2s+V5')
INORDER_VARIANTS = {
    'B0': {}, 'B1': {'swap': True},
    'B2-load': {'lsu': ('load',)}, 'B2': {'lsu': ('load', 'store')},
    'B3': {'mul': True}, 'B4': {'dual_control': True},
    'B5': {'mul_latency': 2}, 'B6': {'predictor': (128, 2048, 8)},
    'B6-ras': {'predictor': (64, 1024, 8)}, 'B7': {'late_jalr': True},
}
VARIANTS += tuple(INORDER_VARIANTS)
SLOT_CAUSES = ('effective', 'wrong_path', 'redirect_e', 'redirect_m', 'redirect_d',
               'frontend', 'load_use',
               'other_result', 'csr_serial', 'pair_raw', 'pair_structural',
               'pair_type', 'pair_one', 'training_structural')
PAIR_CAUSES = {5: 'pair_raw', 6: 'pair_structural', 7: 'pair_type', 8: 'pair_one'}


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
    trace_index: int = -1
    counted_issue: bool = False
    late: bool = False
    late_store_data: bool = False
    deferred_control: bool = False


class Predictor:
    """C-E2 grouped BTB/gshare/RAS algorithm, scheduled at F1 and E like the RTL."""

    def __init__(self, btb_size, pht_size, group_bytes, ras_size=4, gshare_pc_shift=1):
        self.btb = [None] * btb_size
        self.pht = [1] * pht_size
        self.history = 0
        self.gshare_pc_shift = gshare_pc_shift
        self.shift = group_bytes.bit_length() - 1
        self.stack = [0] * ras_size
        self.pointer = 0
        self.count = 0

    def snapshot(self):
        return self.pointer, self.count, self.stack[(self.pointer - 1) % len(self.stack)]

    def action(self, instruction):
        if instruction.pop and self.count:
            self.pointer = (self.pointer - 1) % len(self.stack)
            self.count -= 1
        if instruction.push:
            self.stack[self.pointer] = instruction.pc + instruction.size
            self.pointer = (self.pointer + 1) % len(self.stack)
            self.count = min(len(self.stack), self.count + 1)

    def restore(self, record):
        self.pointer, self.count, top = record.checkpoint
        if self.count:
            self.stack[(self.pointer - 1) % len(self.stack)] = top
        self.action(record.instruction)

    def query(self, pc):
        entry = self.btb[(pc >> self.shift) & (len(self.btb) - 1)]
        if entry and (entry[0].pc >> self.shift != pc >> self.shift or entry[0].pc < pc):
            entry = None
        taken = False
        target = 0
        if entry:
            instruction, target = entry
            index = ((instruction.pc >> self.gshare_pc_shift) ^ self.history) & (
                len(self.pht) - 1)
            taken = instruction.kind != 'branch' or self.pht[index] >= 2
            if instruction.pop and self.count:
                target = self.stack[(self.pointer - 1) % len(self.stack)]
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


def fetch_request(predictor, pc, cross, group_bytes=8, dual_query=False,
                  query_override=None):
    """F1 hit request, including group truncation and a crossing instruction tail."""
    query = predictor.query(pc)
    first_query = query
    second_query = None
    midpoint = (pc & -group_bytes) + 8
    if dual_query and pc < midpoint and cross is None:
        second_query = predictor.query(midpoint)
        if not query[1] and second_query[1]:
            query = second_query
    group_end = (pc & -group_bytes) + group_bytes
    if query_override is not None:
        query = first_query = query_override
        second_query = None
    entry, taken, target, history, checkpoint = query
    request_end = group_end
    next_cross = None
    if cross is not None:
        query = (None, False, 0, history, checkpoint)
        request_end = pc + 2
        next_fetch = cross
    elif taken:
        branch_end = entry[0].pc + entry[0].size
        request_end = min(group_end, branch_end)
        if branch_end > group_end:
            next_fetch = group_end
            next_cross = target
        else:
            next_fetch = target
    else:
        next_fetch = group_end
    if dual_query and second_query:
        response = [(address, first_query if address < midpoint else second_query)
                    for address in range(pc, request_end, 2)]
    else:
        response = [(address, query) for address in range(pc, request_end, 2)]
    return response, next_fetch, next_cross, query


def fill_ib(program, ib, halfwords, depth=4, pht_size=1024, gshare_pc_shift=1):
    """F2 appends up to two complete instructions using the saved F1 metadata."""
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
        ib.append(Record(instruction, hit, hit and taken, target,
                         ((pc >> gshare_pc_shift) ^ history) & (pht_size - 1), checkpoint))
        del halfwords[:length]


def simulate(program, trace, begin, end, variant='V0', *, e_penalty=3, d_penalty=2,
             load_latency=2, mul_latency=3, perfect_prediction=False,
             perfect_frontend=False, relax_raw=False, all_slot1_types=False,
             statistics=None, btb_entries=None, gshare_entries=None, ras_entries=None,
             gshare_pc_shift=1, taken_bubble=0):
    changes = INORDER_VARIANTS.get(variant, {})
    if variant in INORDER_VARIANTS:
        variant = 'L2b+V5'
    mul_latency = changes.get('mul_latency', mul_latency)
    swap = variant in {'V1', 'V3', 'V3s', 'V3+V4a', 'V3+V4b', 'V3+V5'}
    swap |= changes.get('swap', False)
    late_backend = variant.startswith('L')
    late_both = variant in {'L2', 'L2+V5', 'L2b', 'L2b+V5', 'L2s', 'L2s+V5'}
    late_branch = variant in {'L2b', 'L2b+V5'}
    late_store = variant in {'L2s', 'L2s+V5'}
    branch_lane = late_backend or variant in {
        'V2', 'V2s', 'V2s+V5', 'V3', 'V3s', 'V3+V4a', 'V3+V4b', 'V3+V5'}
    single_control = late_backend or variant in {'V2s', 'V2s+V5', 'V3s'}
    single_control &= not changes.get('dual_control', False)
    late_controls = {'branch', 'jalr'} if changes.get('late_jalr') else {'branch'}
    dual_query = variant in {'V4b', 'V3+V4b'}
    group_bytes = 16 if variant in {'V4a', 'V3+V4a', 'V4b', 'V3+V4b'} else 8
    depth = 8 if group_bytes == 16 else 4
    large_predictor = variant in {'V5', 'V3+V5', 'V2s+V5'} or (
        late_backend and variant.endswith('+V5'))
    btb, pht = (64, 1024) if large_predictor else (32, 512)
    btb, pht, ras = changes.get('predictor', (btb, pht, 4))
    btb = btb if btb_entries is None else btb_entries
    pht = pht if gshare_entries is None else gshare_entries
    ras = ras if ras_entries is None else ras_entries
    predictor = Predictor(btb, pht, 8 if dual_query else group_bytes, ras, gshare_pc_shift)
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
    late_retired = [0, 0, 0]
    training_pending = deque()
    training_conflicts = 0
    training_peak = 0
    training_over_one = 0
    slots = dict.fromkeys(SLOT_CAUSES, 0)
    division_left = 0
    recovery = None
    fetch_delay = 0
    ideal_wait = 0
    oracle_cursor = 0
    front_cursor = 0
    ideal_group = None
    ideal_query = None
    tail_pc = end + program[end].size
    latencies = {'load': load_latency, 'mul': mul_latency, 'csr': 2}
    long_results = max(load_latency, mul_latency) > 3
    if statistics is not None:
        statistics.update(load_use_load_address_cycles=0, load_use_store_address_cycles=0)

    def hazard(instruction, forwarded=0):
        waits = 0
        for source in instruction.sources:
            if source != forwarded:
                waits |= wait_kind.get(source, 0)
        return waits

    def schedule(instruction, lane, older=None, older_late=False):
        needs = []
        for source in instruction.sources:
            if older and older.rd and source == older.rd:
                latency = 2 if older_late and older.kind == 'alu' else latencies.get(
                    older.kind, 1)
                needs.append(0 if relax_raw else latency)
            else:
                needs.append(ready_in.get(source, 0))
        if not any(needs):
            return True, False, False
        if (instruction.kind == 'alu' and (lane == 1 or late_both)) or (
                instruction.kind in late_controls and late_branch):
            if max(needs) <= 1:
                return True, True, False
        if instruction.kind == 'store' and late_store and lane == 0:
            # GNU numeric store operands are data first, then the address base.
            if needs[0] <= 1 and not any(needs[1:]):
                return True, False, True
        return False, False, False

    def request(pc, cross):
        nonlocal oracle_cursor
        query = None
        group_end = (pc & -group_bytes) + group_bytes
        if perfect_prediction and cross is None:
            query = (None, False, 0, predictor.history, predictor.snapshot())
            while oracle_cursor < len(trace) and trace[oracle_cursor] < group_end:
                instruction = program[trace[oracle_cursor]]
                next_pc = trace[oracle_cursor + 1] if oracle_cursor + 1 < len(trace) else end + 4
                oracle_cursor += 1
                if instruction.kind in {'jal', 'jalr'} or (
                        instruction.kind == 'branch' and
                        next_pc != instruction.pc + instruction.size):
                    query = ((instruction, next_pc), True, next_pc,
                             predictor.history, predictor.snapshot())
                    break
        return fetch_request(predictor, pc, cross, group_bytes, dual_query, query)

    def refill_ideal():
        nonlocal front_cursor, ideal_group, ideal_query, tail_pc
        while len(ib) < depth:
            if front_cursor < len(trace):
                pc = trace[front_cursor]
                next_pc = trace[front_cursor + 1] if front_cursor + 1 < len(trace) else end + 4
            else:
                # Only the known sequential stop_time tail is needed before the end retires.
                pc = tail_pc
                next_pc = pc + program[pc].size
                tail_pc = next_pc
            instruction = program[pc]
            if ideal_group != pc >> 3:
                ideal_group = pc >> 3
                ideal_query = predictor.query(pc)
                if ideal_query[1]:
                    predictor.action(ideal_query[0][0])
            entry, taken, target, history, checkpoint = ideal_query
            hit = bool(entry and entry[0].pc == pc)
            if perfect_prediction and instruction.kind in CONTROL:
                hit = True
                taken = instruction.kind != 'branch' or next_pc != pc + instruction.size
                target = next_pc
            ib.append(Record(instruction, hit, hit and taken, target,
                             ((pc >> gshare_pc_shift) ^ history) & (pht - 1), checkpoint))
            front_cursor += 1
            if next_pc != pc + instruction.size or (hit and taken):
                ideal_group = None

    while True:
        ending = False
        retired_controls = 0
        retired_late = [0, 0, 0]
        for record in w:
            pc = record.instruction.pc
            ending |= pc == end
            active |= pc == begin
            retired_controls += record.instruction.kind in CONTROL
            if record.late:
                retired_late[0 if record.instruction.kind == 'alu' else 1] += 1
            retired_late[2] += record.late_store_data
        if ending:
            break
        blocked_ideal = False
        if perfect_frontend:
            if ideal_wait:
                ideal_wait -= 1
                blocked_ideal = True
            else:
                refill_ideal()
        events = [0] * 17
        retire_event = 1 if len(w) == 2 else 2 if w else 3
        events[4] = retired_controls

        # A deferred M branch is older than every E record and resolves first.
        m_redirect = None
        m_surviving = m
        if late_branch:
            for index, record in enumerate(m):
                instruction = record.instruction
                if (record.late and instruction.kind in late_controls) or record.deferred_control:
                    taken = (instruction.kind in {'jal', 'jalr'} or
                             record.next_pc != instruction.pc + instruction.size)
                    if not record.d_redirect and (record.taken != taken or (
                            taken and record.target != record.next_pc)):
                        m_redirect = record
                        m_surviving = m[:index + 1]
                        break
        m_training = [r for r in m_surviving if (
            r.late and r.instruction.kind in late_controls) or r.deferred_control]
        bounded_training = changes.get('training_capacity') == 1
        m_stall = bounded_training and len(training_pending) + len(m_training) > 2
        if m_stall:
            m_redirect = None

        # E resolves before D can issue. A wrong younger member is squashed here.
        redirect = None
        surviving = []
        for record in (() if m_redirect or m_stall else e):
            instruction = record.instruction
            surviving.append(record)
            if (record.late and instruction.kind in late_controls) or record.deferred_control:
                continue
            actual_taken = (instruction.kind in {'jal', 'jalr'} or
                            (instruction.kind == 'branch' and
                             record.next_pc != instruction.pc + instruction.size))
            wrong = (record.taken != actual_taken or
                     (record.taken and record.target != record.next_pc))
            if wrong and not record.d_redirect:
                redirect = record
                break
        e_training = [r for r in surviving if r.instruction.kind in CONTROL and not (
            (r.late and r.instruction.kind in late_controls) or r.deferred_control)]
        e_stall = m_stall or (bounded_training and
            len(training_pending) + len(m_training) + len(e_training) > 2)
        if e_stall:
            redirect = None
        div_wait = bool(not m_redirect and not e_stall and division_left and
                        any(r.instruction.kind == 'div' for r in surviving))
        events[10] = int(div_wait)
        if div_wait:
            division_left -= 1
            redirect = None
        events[16] = int(m_redirect is not None or redirect is not None)
        available = not (m_redirect or redirect or div_wait or blocked_ideal or e_stall)
        events[12] = int(not ib and available)
        if ib and e:
            inst = ib[0].instruction
            events[9] = int(any(r.instruction.kind == 'load' and r.instruction.rd and
                               r.instruction.rd in inst.sources for r in e))

        issued = []
        d_redirect = None
        reason = 0
        pair_event = 0
        # Build closest-producer readiness once, including younger WAW priority.
        wait_kind = {}
        ready_in = {}
        stages = ((3, w), (2, m), (1, e)) if long_results else ((2, m), (1, e))
        for age, records in stages:
            for record in records:
                producer = record.instruction
                if producer.rd:
                    code = 1 if producer.kind == 'load' else 2
                    latency = 2 if record.late and producer.kind == 'alu' else latencies.get(
                        producer.kind, 1)
                    wait_kind[producer.rd] = code if latency > age else 0
                    if late_backend:
                        ready_in[producer.rd] = max(0, latency - age)
        front_empty = not ib
        trace_exhausted = cursor >= len(trace)
        older_waits = hazard(ib[0].instruction) if ib else 0
        older_late = older_store = False
        if ib and late_backend:
            allowed, older_late, older_store = schedule(ib[0].instruction, 0)
            if allowed:
                older_waits = 0
        csr_wait = bool(ib and ib[0].instruction.kind == 'csr' and (e or m))
        if ib and available and cursor < len(trace):
            older = ib[0].instruction
            if not older_waits and not csr_wait:
                count = 1
                reason = 8
                younger_late = younger_store = False
                if len(ib) >= 2:
                    younger = ib[1].instruction
                    raw = not relax_raw and older.rd and older.rd in younger.sources
                    forwarded = older.rd if relax_raw else 0
                    structural = older.kind in {'csr', 'serial'} or hazard(younger, forwarded)
                    if late_backend:
                        allowed, younger_late, younger_store = schedule(
                            younger, 1, older, older_late)
                        if allowed:
                            raw = False
                            structural = older.kind in {'csr', 'serial'}
                    if all_slot1_types and younger.kind in {'csr', 'serial'}:
                        structural = True
                    supported = (younger.kind == 'alu' or
                                 (branch_lane and younger.kind in {'branch', 'jal'}))
                    if younger.kind in changes.get('lsu', ()):
                        supported = True
                        structural |= older.kind in {'load', 'store'}
                    if younger.kind == 'mul' and changes.get('mul'):
                        supported = True
                        structural |= older.kind == 'mul'
                    if all_slot1_types:
                        supported = younger.kind != 'illegal'
                    if single_control and older.kind in CONTROL and younger.kind in CONTROL:
                        supported = False
                    older_supported = older.kind == 'alu' or (
                        branch_lane and older.kind in {'branch', 'jal'})
                    exchanged = swap and older_supported and not supported
                    exchanged = exchanged and younger.kind not in {'csr', 'serial', 'illegal'}
                    if single_control and older.kind in CONTROL and younger.kind in CONTROL:
                        exchanged = False
                    reason = 5 if raw else 6 if structural else 7 if not (
                        supported or exchanged) else 0
                    if not reason:
                        count = 2
                if older.kind == 'jal' and not ib[0].hit and not perfect_prediction:
                    count = 1
                    d_redirect = ib[0]
                    d_redirect.d_redirect = True
                    events[16] = 1
                elif (count == 2 and ib[1].instruction.kind == 'jal' and not ib[1].hit
                      and not perfect_prediction):
                    d_redirect = ib[1]
                    d_redirect.d_redirect = True
                    events[16] = 1
                if count == 1 and reason:
                    pair_event = reason
                for slot in range(count):
                    record = ib.popleft()
                    instruction = record.instruction
                    record.trace_index = cursor
                    record.counted_issue = active
                    record.late = older_late if slot == 0 else younger_late
                    record.late_store_data = older_store if slot == 0 else younger_store
                    record.deferred_control = bool(
                        changes.get('dual_control') and slot == 1 and older_late and
                        older.kind in CONTROL and instruction.kind in CONTROL)
                    record.next_pc = trace[cursor + 1] if cursor + 1 < len(trace) else end + 4
                    if cursor < len(trace) and instruction.pc == trace[cursor]:
                        cursor += 1
                    else:
                        speculative = late_branch and any(
                            (r.late and r.instruction.kind in late_controls) or
                            r.deferred_control for r in e)
                        if slot == 0 and not speculative:
                            raise ValueError(f'trace mismatch at commit {cursor}: '
                                             f'fetch PC {instruction.pc:08x}, '
                                             f'Spike PC {trace[cursor]:08x}')
                        # M-resolved branches also permit an entire younger E group to be wrong.
                        record.trace_index = -1
                        record.next_pc = instruction.pc + instruction.size
                    issued.append(record)
                if any(r.instruction.kind == 'div' for r in issued):
                    division_left = 33

        # F2 can append the arriving hit and drain two instructions into IB in the same cycle.
        flush = m_redirect or redirect or d_redirect
        query = None
        if not flush and not perfect_frontend:
            halfwords.extend(pending)
            pending = []
            fill_ib(program, ib, halfwords, depth, pht, gshare_pc_shift)
            if fetch_delay:
                fetch_delay -= 1
            elif len(halfwords) <= group_bytes // 2:
                pending, fetch_pc, cross_target, query = request(fetch_pc, cross_target)
                if query[1]:
                    fetch_delay = taken_bubble

        # All predictor mutations occur at the edge, after the concurrent F1 query.
        m_updates = []
        if late_branch and not m_stall:
            for record in m_surviving:
                if (record.late and record.instruction.kind in late_controls) or (
                        record.deferred_control):
                    m_updates.append(record)
        e_updates = []
        if not div_wait and not e_stall:
            for record in surviving:
                if record.instruction.kind in CONTROL and not (
                        (record.late and record.instruction.kind in late_controls) or
                        record.deferred_control):
                    e_updates.append(record)
        if late_branch:
            training_pending.extend(m_updates)
            training_pending.extend(e_updates)
            if training_pending:
                predictor.update(training_pending.popleft())
        else:
            for record in e_updates:
                predictor.update(record)
        if flush:
            predictor.restore(flush)
            fetch_pc = flush.next_pc
            ib.clear()
            halfwords = []
            pending = []
            cross_target = None
            recovery = 'redirect_m' if m_redirect else 'redirect_e' if redirect else 'redirect_d'
            penalty = e_penalty if m_redirect or redirect else d_penalty
            if late_backend and (m_redirect or redirect):
                cursor = flush.trace_index + 1
            if perfect_frontend:
                cursor = flush.trace_index + 1
                front_cursor = cursor
                ideal_group = None
                tail_pc = end + program[end].size
                ideal_wait = penalty - 1 if m_redirect or redirect else penalty
            else:
                normal = 3 if m_redirect or redirect else 2
                fetch_delay = max(0, penalty - normal)
                if penalty < normal:
                    pending, fetch_pc, cross_target, query = request(fetch_pc, None)
                    if query[1]:
                        predictor.action(query[0][0])
        elif query and query[1]:
            predictor.action(query[0][0])
        if not flush and issued:
            recovery = None
        killed = 0
        if m_stall:
            w = []
        elif e_stall:
            w, m = m_surviving, []
        elif div_wait:
            w, m = m, []
        else:
            if m_redirect:
                killed = sum(r.counted_issue for r in m[len(m_surviving):] + e)
                w, m, e = m_surviving, [], []
                division_left = 0
            else:
                killed = sum(r.counted_issue for r in e[len(surviving):]) if redirect else 0
                w, m, e = m, surviving, issued
        if active:
            cycles += 1
            killed = 0 if div_wait else killed
            slots['effective'] += len(issued) - killed
            slots['wrong_path'] += killed
            empty = 2 - len(issued)
            if empty:
                if e_stall:
                    cause = 'training_structural'
                elif recovery:
                    cause = recovery
                elif front_empty or trace_exhausted and not csr_wait:
                    cause = 'frontend'
                elif not issued and older_waits & 1:
                    cause = 'load_use'
                elif not issued and (older_waits or div_wait):
                    cause = 'other_result'
                elif not issued and csr_wait:
                    cause = 'csr_serial'
                else:
                    cause = PAIR_CAUSES[reason]
                slots[cause] += empty
                if cause == 'load_use' and statistics is not None:
                    consumer = ib[0].instruction
                    if consumer.kind in {'load', 'store'} and (
                            wait_kind.get(consumer.sources[-1], 0) & 1):
                        statistics[f'load_use_{consumer.kind}_address_cycles'] += 1
            counters[retire_event] += 1
            if pair_event:
                counters[pair_event] += 1
            for event in (4, 9, 10, 12, 16):
                counters[event] += events[event]
            for index, count in enumerate(retired_late):
                late_retired[index] += count
            training_conflicts += (len(m_updates) + len(e_updates) > 1)
            training_over_one += len(training_pending) > 1
            training_peak = max(training_peak, len(training_pending))
    result = dict(cycles=cycles, instructions=2 * counters[1] + counters[2],
                  **{f'hpm{i}': counters[i] for i in range(1, 17)})
    result['ipc'] = result['instructions'] / result['cycles']
    result.update({f'slots_{cause}': count for cause, count in slots.items()})
    result.update(late_alu=late_retired[0], late_branch=late_retired[1],
                  late_store_data=late_retired[2], late_instructions=sum(late_retired))
    result['late_share'] = result['late_instructions'] / result['instructions']
    result['training_conflicts'] = training_conflicts
    result['training_peak'] = training_peak
    result['training_over_one'] = training_over_one
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='directory with coremark.elf and spike.log')
    parser.add_argument('--variant', choices=VARIANTS, default='V0')
    parser.add_argument('--e-penalty', type=int, choices=(2, 3, 4), default=3)
    parser.add_argument('--d-penalty', type=int, choices=(1, 2, 3), default=2)
    parser.add_argument('--load-latency', type=int, choices=(1, 2, 3), default=2)
    parser.add_argument('--mul-latency', type=int, choices=(1, 2, 3, 4), default=3)
    parser.add_argument('--perfect-prediction', action='store_true')
    parser.add_argument('--perfect-frontend', action='store_true')
    parser.add_argument('--relax-raw', action='store_true')
    parser.add_argument('--all-slot1-types', action='store_true')
    parser.add_argument('--btb-entries', type=int, choices=(32, 64, 128, 256))
    parser.add_argument('--gshare-entries', type=int, choices=(512, 1024, 2048, 4096))
    parser.add_argument('--ras-entries', type=int, choices=(4, 8))
    parser.add_argument('--gshare-pc-shift', type=int, choices=(1, 2), default=1)
    args = parser.parse_args()
    program, symbols, trace = program_and_trace(args.directory)
    print(json.dumps(simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                              args.variant, e_penalty=args.e_penalty, d_penalty=args.d_penalty,
                              load_latency=args.load_latency, mul_latency=args.mul_latency,
                              perfect_prediction=args.perfect_prediction,
                              perfect_frontend=args.perfect_frontend, relax_raw=args.relax_raw,
                              all_slot1_types=args.all_slot1_types,
                              btb_entries=args.btb_entries,
                              gshare_entries=args.gshare_entries,
                              ras_entries=args.ras_entries,
                              gshare_pc_shift=args.gshare_pc_shift), indent=2))


if __name__ == '__main__':
    main()
