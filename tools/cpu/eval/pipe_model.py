#!/usr/bin/env python3
# File: pipe_model.py; Spec: cpu-spec 2.3, 4.1-4.4, 4.10-4.11, 7.1; Clock: host.
# Replay Spike commits through a hit-only, cycle-stepped frontend and dual-issue backend.
# Retain speculative fetch/F1 indices; train surviving E/M controls under C-E7 late execution.
"""Cycle approximation, with HPM windows defined by retired start_time/stop_time PCs."""
import argparse
from bisect import bisect_left, bisect_right
from collections import deque
from dataclasses import dataclass, replace
import json
from pathlib import Path
import subprocess

from ipc_structures import (Direction, FUSIONS, Macro, SavedHistory, destinations,
                            fuse_program, operation)
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
    lcb: bool = False
    result_latency: int = 0
    direction_meta: object = None
    cache_group: int = -1
    early_load: bool = False
    adjacent_base: bool = False
    serial_pair: bool = False
    memory_checked: bool = False


class Predictor:
    """C-E2 grouped BTB/gshare/RAS algorithm, scheduled at F1 and E like the RTL."""

    def __init__(self, btb_size, pht_size, group_bytes, ras_size=4,
                 gshare_pc_shift=1, direction=None, registered=False, second_level=False):
        self.registered = registered
        self.second_level = second_level
        self.training = []
        self.btb = [None] * btb_size
        self.pht = [1] * pht_size
        self.history = 0
        self.direction = Direction(direction) if direction else None
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
        history = self.history
        if self.direction and entry and instruction.kind == 'branch':
            second, token = self.direction.predict(instruction.pc, taken, index)
            if not self.second_level:
                taken = second
            history = SavedHistory(history)
            history.direction = (instruction.pc, token)
            history.second = second
        return entry, taken, target, history, self.snapshot()

    def edge(self, records):
        """4.4: F1 queries old state; registered decisions write one edge later."""
        for record in self.training if self.registered else records:
            self.update(record)
        if self.registered:
            self.training = list(records)

    def update(self, record):
        instruction = record.instruction
        if instruction.kind not in CONTROL:
            return
        taken = record.next_pc != instruction.pc + instruction.size
        target = record.next_pc if instruction.kind == 'jalr' else instruction.target
        self.btb[(instruction.pc >> self.shift) & (len(self.btb) - 1)] = instruction, target
        if instruction.kind == 'branch':
            if self.direction and record.direction_meta is not None:
                self.direction.update(instruction.pc, taken, record.direction_meta)
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
        saved = getattr(history, 'direction', None)
        if saved and saved[0] == pc:
            ib[-1].direction_meta = saved[1]
        del halfwords[:length]


def early_address_allowed(instruction, older, e, m, w, mul_latency):
    """4.10 exclusion list, using stage occupancy at the start of D."""
    base = instruction.sources[-1] if instruction.sources else 0
    if not base:
        return True
    if isinstance(instruction, Macro):
        return False
    if any(base in destinations(r.instruction) for r in older + e):
        return False
    # A fused ADD+load's first destination belongs to its registered ALU result.
    if any(r.instruction.kind in {'load', 'csr'} and
           base == r.instruction.rd for r in m):
        return False
    return not any(r.instruction.kind == 'mul' and age < mul_latency and
                   base in destinations(r.instruction)
                   for age, group in ((1, e), (2, m), (3, w)) for r in group)


def lcb_allowed(instruction, e, wait_kind):
    """4.11: every unavailable source is an E load with result latency exactly two."""
    if instruction.kind != 'branch':
        return False
    pending = {source for source in instruction.sources if wait_kind.get(source, 0)}
    loads = {r.instruction.rd for r in e if r.instruction.kind == 'load' and
             (r.result_latency or 2) == 2}
    return bool(pending) and pending <= loads and all(wait_kind[s] == 1 for s in pending)


def simulate(program, trace, begin, end, variant='V0', *, e_penalty=3, d_penalty=2,
             load_latency=2, mul_latency=3, perfect_prediction=False,
             perfect_frontend=False, relax_raw=False, all_slot1_types=False,
             statistics=None, btb_entries=None, gshare_entries=None, ras_entries=None,
             gshare_pc_shift=1, taken_bubble=0, lcb=None, fusion=(), loop_cache=False,
             early_address=0, direction_predictor=None, serial_alu=None,
             registered_control=False, second_level=False, dual_lsu=False, timeline=None,
             lcb_split=False, frontend_probe=None, frontend_registered_margin=False,
             alu_latency=1, shift_latency=None, compare_latency=None,
             decode_split=False, branch_register=False, memory_probe=None,
             line_predictor=False):
    if fusion:
        program, trace = fuse_program(program, trace, fusion, begin, end)
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
    predictor = Predictor(btb, pht, 8 if dual_query else group_bytes, ras,
                          gshare_pc_shift, direction_predictor, registered_control, second_level)
    experimental = dict(lcb_branches=0, lcb_misses=0, fused=0, early_loads=0,
                        loads=0, adjacent_load_base=0, serial_pairs=0,
                        cache_instructions=0, cache_hits=0, branches=0, direction_misses=0,
                        f2_corrections=0)
    retired_instructions = 0
    last_writes = {}
    previous_instruction = None
    cache = {}
    static_pcs = sorted(program) if loop_cache else []
    learned_groups = deque(maxlen=16)
    replay = None
    replay_position = 0
    cache_sequence = 0
    ib = deque()
    halfwords = []
    pending = []
    fetch_pc = trace[0]
    cross_target = None
    e, m, w = [], [], []
    w2 = []
    cursor = 0
    active = False
    cycles = 0
    tick = 0
    counters = [0] * 17
    late_retired = [0, 0, 0]
    training_pending = deque()
    training_conflicts = 0
    training_peak = 0
    training_over_one = 0
    slots = dict.fromkeys(SLOT_CAUSES, 0)
    division_left = 0
    recovery = None
    registered_redirect = None
    extra_redirect = None
    extra_training = []
    decode_pending = []
    line_targets = [None] * 128
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

    def hazard(instruction, forwarded=()):
        waits = 0
        for source in instruction.sources:
            if source not in forwarded:
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
        nonlocal oracle_cursor, fetch_delay
        if frontend_probe is not None:
            fetch_delay += frontend_probe.query(pc, active)
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
            saved = getattr(history, 'direction', None)
            if saved and saved[0] == pc:
                ib[-1].direction_meta = saved[1]
            front_cursor += 1
            if next_pc != pc + instruction.size or (hit and taken):
                ideal_group = None

    while True:
        # T2 FE option: reserve from the eight physical IB/stream entries at
        # cycle start, including the outstanding response; D pops are not credits yet.
        frontend_margin = 8 - len(ib) - (len(halfwords) + len(pending)) // 2
        applied_redirect = registered_redirect
        registered_redirect = extra_redirect
        extra_redirect = None
        # Incremental registered miss/failure repair freezes all stages before retirement.
        memory_delay = 0
        if memory_probe is not None:
            for record in m:
                if not record.memory_checked and record.trace_index >= 0:
                    record.memory_checked = True
                    memory_delay += memory_probe.query(record, active, e)
        if memory_delay:
            tick += memory_delay
            cycles += memory_delay * active
        if loop_cache:
            if replay is None and ib:
                # A loop head may be in the second half of a normal issue group.
                # Preserve older queued instructions; enter at any cached group start.
                starts = {group[0][0].pc: (groups, position)
                          for groups in cache.values() for position, group in enumerate(groups)}
                entry = next(((index, starts[record.instruction.pc])
                              for index, record in enumerate(ib)
                              if record.instruction.pc in starts), None)
                if entry is not None:
                    index, (replay, replay_position) = entry
                    prefix = list(ib)[:index]
                    ib.clear()
                    ib.extend(prefix)
                    halfwords, pending = [], []
                    if active:
                        experimental['cache_hits'] += 1
            if replay is not None and len(ib) <= depth - 2:
                group = replay[replay_position]
                cache_sequence += 1
                for instruction, next_pc in group:
                    query = predictor.query(instruction.pc)
                    _, _, _, history, checkpoint = query
                    taken = instruction.kind in CONTROL and (
                        instruction.kind != 'branch' or
                        next_pc != instruction.pc + instruction.size)
                    rec = Record(instruction, instruction.kind in CONTROL, taken, next_pc,
                                 ((instruction.pc >> gshare_pc_shift) ^ history) & (pht - 1),
                                 checkpoint, cache_group=cache_sequence)
                    saved = getattr(history, 'direction', None)
                    if saved and saved[0] == instruction.pc:
                        rec.direction_meta = saved[1]
                    ib.append(rec)
                    if taken:
                        predictor.action(instruction)
                replay_position = (replay_position + 1) % len(replay)
        ending = False
        retired_controls = 0
        retired_late = [0, 0, 0]
        retirement = w2 if registered_control else w
        for record in retirement:
            pc = record.instruction.pc
            if frontend_probe is not None and record.instruction.bits == 0x0000100f:
                frontend_probe.invalidate()
            ending |= pc == end
            active |= pc == begin
            retired_controls += record.instruction.kind in CONTROL
            if active and pc != end:
                inst = record.instruction
                retired_instructions += len(inst.members) if isinstance(inst, Macro) else 1
                experimental['fused'] += isinstance(inst, Macro)
                if inst.kind == 'load':
                    experimental['loads'] += 1
                    experimental['early_loads'] += record.early_load
                    experimental['adjacent_load_base'] += record.adjacent_base
                experimental['serial_pairs'] += record.serial_pair
                experimental['lcb_branches'] += record.lcb
                taken = record.next_pc != pc + inst.size
                wrong = record.taken != taken or (taken and record.target != record.next_pc)
                experimental['lcb_misses'] += record.lcb and wrong
                if inst.kind == 'branch':
                    experimental['branches'] += 1
                    experimental['direction_misses'] += record.taken != taken
                if record.cache_group >= 0:
                    experimental['cache_instructions'] += 1
            if record.late:
                retired_late[0 if record.instruction.kind == 'alu' else 1] += 1
            retired_late[2] += record.late_store_data
        if ending:
            break
        if registered_control:
            w2 = w
        if timeline is not None:
            timeline.append((tick, 'stages', tuple(r.instruction.pc for r in e),
                             tuple(r.instruction.pc for r in m)))
        blocked_ideal = False
        if perfect_frontend:
            if ideal_wait:
                ideal_wait -= 1
                blocked_ideal = True
            else:
                refill_ideal()
        events = [0] * 17
        retire_event = 1 if len(retirement) == 2 else 2 if retirement else 3
        events[4] = retired_controls

        # A deferred M branch is older than every E record and resolves first.
        m_redirect = None
        m_surviving = m
        if (late_branch or lcb or registered_control) and not applied_redirect:
            for index, record in enumerate(m):
                instruction = record.instruction
                system_restart = registered_control and instruction.bits in {
                    0x30200073, 0x10500073, 0x0000100f}
                if system_restart or ((record.late and instruction.kind in late_controls) or
                                      record.deferred_control or record.lcb):
                    taken = (instruction.kind in {'jal', 'jalr'} or
                             record.next_pc != instruction.pc + instruction.size)
                    if system_restart or (not record.d_redirect and (
                            record.taken != taken or (taken and record.target != record.next_pc))):
                        m_redirect = record
                        m_surviving = m[:index + 1]
                        break
        m_training = [r for r in m_surviving if (
            r.late and r.instruction.kind in late_controls) or r.deferred_control or r.lcb]
        bounded_training = changes.get('training_capacity') == 1
        m_stall = bounded_training and len(training_pending) + len(m_training) > 2
        if m_stall:
            m_redirect = None

        # E resolves before D can issue. A wrong younger member is squashed here.
        redirect = None
        surviving = []
        resolving_e = e
        if applied_redirect:
            resolving_e = e[:e.index(applied_redirect[1]) + 1] if (
                applied_redirect[0] == 'd') else []
        for record in (() if m_redirect or m_stall else resolving_e):
            instruction = record.instruction
            surviving.append(record)
            if ((record.late and instruction.kind in late_controls) or
                    record.deferred_control or record.lcb or registered_control and
                    instruction.bits in {0x30200073, 0x10500073, 0x0000100f}):
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
            (r.late and r.instruction.kind in late_controls) or r.deferred_control or r.lcb)]
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
        available = not (m_redirect or redirect or applied_redirect or div_wait or
                         blocked_ideal or e_stall or registered_redirect)
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
        if decode_split:
            # D1 reserves operands for next-cycle D2. A pending D2 producer is
            # one E-entry interval older; E/M/W producers are two/three/four older.
            stages = tuple((age + 1, records) for age, records in stages) + (
                (1, decode_pending),)
        for age, records in stages:
            for record in records:
                producer = record.instruction
                for destination in destinations(producer):
                    if not destination:
                        continue
                    code = 1 if producer.kind == 'load' else 2
                    latency = record.result_latency or (2 if record.late and producer.kind == 'alu'
                                                       else latencies.get(producer.kind, 1))
                    if isinstance(producer, Macro) and destination != producer.rd:
                        latency = 1
                    wait_kind[destination] = code if latency > age else 0
                    if late_backend:
                        ready_in[destination] = max(0, latency - age)
        front_empty = not ib
        trace_exhausted = cursor >= len(trace)
        older_waits = hazard(ib[0].instruction) if ib else 0
        older_late = older_store = False
        if ib and late_backend:
            allowed, older_late, older_store = schedule(ib[0].instruction, 0)
            if allowed:
                older_waits = 0
        lcb_control_block = lcb == 'v017' and any(r.lcb for r in e)
        if ib and lcb_control_block and ib[0].instruction.kind in CONTROL:
            older_waits |= 2
        older_lcb = False
        if lcb == 'v017' and ib:
            older_lcb = not lcb_control_block and lcb_allowed(ib[0].instruction, e, wait_kind)
            if older_lcb:
                older_waits = 0
        if (lcb and lcb != 'v017' and ib and
                ib[0].instruction.kind == 'branch' and previous_instruction):
            inst = ib[0].instruction
            preceding, issue_cycle = previous_instruction
            if (preceding.kind == 'load' and preceding.rd in inst.sources and preceding.rd
                    and inst.pc == preceding.pc + preceding.size):
                # M comparison can consume the previous cycle's load in M; other inputs
                # must already be available. Never pair a load and its branch in E.
                if issue_cycle == tick - 1 and not hazard(inst, (preceding.rd,)):
                    older_waits = 0
                    older_lcb = True
        csr_wait = bool(ib and ib[0].instruction.kind == 'csr' and (decode_pending or e or m))
        if ib and available and cursor < len(trace):
            older = ib[0].instruction
            if not older_waits and not csr_wait:
                count = 1
                reason = 8
                younger_late = younger_store = younger_lcb = False
                if len(ib) >= 2:
                    younger = ib[1].instruction
                    chain = serial_alu and older.kind == 'alu' and (
                        serial_alu == 'any' or operation(older) in {
                            'addi', 'lui', 'andi', 'ori', 'xori', 'and', 'or', 'xor',
                            'slli', 'srli', 'srai', 'sll', 'srl', 'sra'})
                    forward = relax_raw or chain
                    writes = destinations(older)
                    raw = not forward and any(rd and rd in younger.sources for rd in writes)
                    forwarded = writes if forward else ()
                    if lcb == 'v017':
                        younger_lcb = lcb_allowed(younger, e, wait_kind)
                    structural = older.kind in {'csr', 'serial'} or (
                        hazard(younger, forwarded) and not younger_lcb)
                    if late_backend:
                        allowed, younger_late, younger_store = schedule(
                            younger, 1, older, older_late)
                        if allowed:
                            raw = False
                            structural = older.kind in {'csr', 'serial'}
                    if lcb_control_block and younger.kind in CONTROL:
                        structural = True
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
                    if dual_lsu and older.kind in {'load', 'store'} and (
                            younger.kind in {'load', 'store'}):
                        from wide_model import fits
                        supported = fits([older, younger], 2, 2, 2, 1, False)
                    if single_control and older.kind in CONTROL and younger.kind in CONTROL:
                        supported = False
                    older_supported = older.kind == 'alu' or (
                        branch_lane and older.kind in {'branch', 'jal'})
                    exchanged = swap and older_supported and not supported
                    exchanged = exchanged and younger.kind not in {'csr', 'serial', 'illegal'}
                    if single_control and older.kind in CONTROL and younger.kind in CONTROL:
                        exchanged = False
                    if chain and exchanged and not relax_raw:
                        raw = any(rd and rd in younger.sources for rd in writes)
                    if ((ib[0].cache_group >= 0 or ib[1].cache_group >= 0) and
                            ib[0].cache_group != ib[1].cache_group):
                        supported = exchanged = False
                    reason = 5 if raw else 6 if structural else 7 if not (
                        supported or exchanged) else 0
                    if not reason:
                        count = 2
                        if chain and any(rd and rd in younger.sources for rd in writes):
                            ib[1].serial_pair = True
                if older_lcb and lcb == 'v017' and count == 2:
                    count = 1 if lcb_split else 0
                    if count:
                        reason = 6
                    if not count:
                        older_waits = hazard(older)
                if count and older.kind == 'jal' and not ib[0].hit and not perfect_prediction:
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
                    record.lcb = older_lcb if slot == 0 else younger_lcb
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
                        speculative = bool(
                            applied_redirect or registered_redirect or registered_control and (
                            m_redirect or redirect or any(r.instruction.bits in {
                                0x30200073, 0x10500073, 0x0000100f} for r in e + m)))
                        speculative |= decode_split and any(
                            r.instruction.kind in CONTROL for r in decode_pending)
                        speculative |= bool(late_branch or lcb) and any(
                            (r.late and r.instruction.kind in late_controls) or
                            r.deferred_control or r.lcb for r in e)
                        if slot == 0 and not speculative:
                            raise ValueError(f'trace mismatch at commit {cursor}: '
                                             f'fetch PC {instruction.pc:08x}, '
                                             f'Spike PC {trace[cursor]:08x}')
                        # M-resolved branches also permit an entire younger E group to be wrong.
                        record.trace_index = -1
                        record.next_pc = instruction.pc + instruction.size
                    if instruction.kind == 'alu' and (alu_latency != 1 or
                            shift_latency is not None or compare_latency is not None):
                        shift = operation(instruction) in {
                            'slli', 'srli', 'srai', 'sll', 'srl', 'sra'}
                        compare = (instruction.bits & 127 in {0x13, 0x33} and
                                   (instruction.bits >> 12) & 7 in {2, 3})
                        latency = alu_latency
                        if shift and shift_latency is not None:
                            latency = shift_latency
                        if compare and compare_latency is not None:
                            latency = compare_latency
                        record.result_latency = max(2 if record.late else 1, latency)
                    if instruction.kind == 'load' and early_address:
                        base = instruction.sources[-1] if instruction.sources else 0
                        recent = last_writes.get(base)
                        if early_address == 'v017':
                            if decode_split:
                                # Query is in D2 next cycle: present D2/E/M become E/M/W.
                                early = early_address_allowed(
                                    instruction, issued, decode_pending, e, m, mul_latency)
                            else:
                                early = early_address_allowed(instruction, issued, e, m, w,
                                                              mul_latency)
                        else:
                            early = not base or recent is None or tick - recent > early_address
                        if isinstance(instruction, Macro):
                            # The fused ADD is itself writing the load's architectural base.
                            early = False
                        record.result_latency = 1 if early else load_latency
                        record.early_load = early
                        record.adjacent_base = isinstance(instruction, Macro) or bool(
                            record.trace_index > 0 and base and
                            base in destinations(program[trace[record.trace_index - 1]]))
                    for destination in destinations(instruction):
                        if destination:
                            last_writes[destination] = tick
                    previous_instruction = instruction, tick
                    issued.append(record)
                if any(r.instruction.kind == 'div' for r in issued):
                    division_left = 33

        # F2 can append the arriving hit and drain two instructions into IB in the same cycle.
        decision = m_redirect or redirect or d_redirect
        decision_stage = 'm' if m_redirect else 'e' if redirect else 'd'
        if decode_split and decision_stage in {'e', 'm'} and decision:
            decode_pending = []
        if registered_control and decision:
            # An older E/M redirect cancels a younger D redirect still in its register.
            if decision_stage in {'e', 'm'} and registered_redirect and (
                    registered_redirect[0] == 'd'):
                registered_redirect = None
            if (branch_register and decision_stage == 'e' or
                    decode_split and decision_stage == 'd'):
                extra_redirect = (decision_stage, decision)
            else:
                registered_redirect = (decision_stage, decision)
            recovery = 'redirect_' + decision_stage
        flush = applied_redirect[1] if applied_redirect else (
            None if registered_control else decision)
        flush_stage = applied_redirect[0] if applied_redirect else decision_stage
        if timeline is not None:
            if decision:
                timeline.append((tick, 'resolve', decision.instruction.pc, decision_stage))
            if flush:
                timeline.append((tick, 'redirect', flush.instruction.pc, flush_stage))
        query = None
        if not flush and not perfect_frontend and replay is None:
            correction = False
            if second_level and pending:
                pc, meta = pending[0]
                entry, taken, target, history, checkpoint = meta
                second = getattr(history, 'second', taken)
                if entry and second != taken:
                    corrected = (entry, second, target, history, checkpoint)
                    pending, fetch_pc, cross_target, _ = fetch_request(
                        predictor, pc, None, group_bytes, query_override=corrected)
                    correction = True
                    if active:
                        experimental['f2_corrections'] += 1
            halfwords.extend(pending)
            pending = []
            fill_ib(program, ib, halfwords, depth, pht, gshare_pc_shift)
            if correction:
                pass
            elif fetch_delay:
                fetch_delay -= 1
            elif len(halfwords) <= group_bytes // 2 and (
                    not frontend_registered_margin or frontend_margin >= 2):
                requested_pc = fetch_pc
                pending, fetch_pc, cross_target, query = request(fetch_pc, cross_target)
                if line_predictor:
                    lp = line_targets[(requested_pc >> 3) & 127]
                    predicted = lp[1] if lp and lp[0] == requested_pc >> 3 else (
                        requested_pc & -group_bytes) + group_bytes
                    # The registered full predictor corrects the line predictor in one cycle.
                    fetch_delay += int(predicted != fetch_pc)
                elif query[1]:
                    fetch_delay += taken_bubble

        # All predictor mutations occur at the edge, after the concurrent F1 query.
        m_updates = []
        if (late_branch or lcb) and not m_stall:
            for record in ([] if applied_redirect and flush_stage == 'm' else m_surviving):
                if (record.late and record.instruction.kind in late_controls) or (
                        record.deferred_control) or record.lcb:
                    m_updates.append(record)
        e_updates = []
        if not div_wait and not e_stall:
            for record in surviving:
                if record.instruction.kind in CONTROL and not (
                        (record.late and record.instruction.kind in late_controls) or
                        record.deferred_control or record.lcb):
                    e_updates.append(record)
        if lcb == 'v017':
            updates = m_updates + e_updates
        elif late_branch or lcb:
            training_pending.extend(m_updates)
            training_pending.extend(e_updates)
            updates = [training_pending.popleft()] if training_pending else []
        else:
            updates = e_updates
        if branch_register:
            updates, extra_training = extra_training, updates
        if line_predictor:
            for record in updates:
                inst = record.instruction
                target = (record.next_pc if record.next_pc != inst.pc + inst.size else
                          (inst.pc & -group_bytes) + group_bytes)
                line_targets[(inst.pc >> 3) & 127] = (inst.pc >> 3, target)
        predictor.edge(updates)
        if timeline is not None:
            for record in updates:
                timeline.append((tick, 'train_capture', record.instruction.pc, predictor.history))
        if loop_cache and not div_wait and not e_stall:
            if m_redirect:
                learned_groups.clear()
            elif surviving:
                learned_groups.append(tuple((r.instruction, r.next_pc) for r in surviving))
                history = list(learned_groups)
                for slot, last in enumerate(surviving):
                    head = last.next_pc
                    if last.instruction.kind not in CONTROL or head > last.instruction.pc:
                        continue
                    static = (bisect_right(static_pcs, last.instruction.pc) -
                              bisect_left(static_pcs, head))
                    if static > 16:
                        continue
                    # Trim both boundary groups at the architectural loop boundary.
                    # Use the latest head, so the entry describes one observed iteration.
                    groups = history[:-1] + [history[-1][:slot + 1]]
                    start = next(((i, j) for i in range(len(groups) - 1, -1, -1)
                                  for j in range(len(groups[i]) - 1, -1, -1)
                                  if groups[i][j][0].pc == head), None)
                    if start is not None:
                        i, j = start
                        groups = [groups[i][j:]] + groups[i + 1:]
                        cache.pop(head, None)
                        while cache and sum(map(len, cache.values())) + len(groups) > 32:
                            del cache[next(iter(cache))]
                        cache[head] = groups
        if flush:
            replay = None
            learned_groups.clear()
            predictor.restore(flush)
            fetch_pc = flush.next_pc
            ib.clear()
            halfwords = []
            pending = []
            cross_target = None
            recovery = 'redirect_' + flush_stage
            penalty = (e_penalty + int(decode_split) + int(branch_register)
                       if flush_stage != 'd' else d_penalty + int(decode_split))
            if flush_stage == 'm' and flush.lcb and lcb in {'registered', 'v017'}:
                penalty += 1
            if registered_control and flush_stage == 'm' and not flush.lcb:
                penalty = 5
            # A JALR can target PC+4: a younger instruction can match the trace
            # before being squashed by its older redirect. Replay it as well.
            cursor = flush.trace_index + 1
            if perfect_frontend:
                front_cursor = cursor
                ideal_group = None
                tail_pc = end + program[end].size
                ideal_wait = penalty - 1 if flush_stage != 'd' else penalty
                if registered_control:
                    ideal_wait -= 1 + int(flush_stage == 'm')
            else:
                normal = (3 if flush_stage != 'd' else 2) + int(registered_control)
                # M comparison itself consumes one of the five lost cycles.
                normal += int(registered_control and flush_stage == 'm')
                normal += int(decode_split) + int(branch_register and flush_stage == 'e')
                fetch_delay = max(0, penalty - normal)
                if penalty < normal:
                    pending, fetch_pc, cross_target, query = request(fetch_pc, None)
                    if query[1]:
                        predictor.action(query[0][0])
        elif query and query[1]:
            predictor.action(query[0][0])
        if not flush and not decision and issued:
            recovery = None
        entering_e = decode_pending if decode_split else issued
        if decode_split:
            if flush:
                decode_pending = []
            elif not (div_wait or e_stall or m_stall):
                decode_pending = issued
        killed = 0
        if applied_redirect:
            if flush_stage == 'd':
                surviving = e[:e.index(flush) + 1]
                w, m, e = m, surviving, []
            elif flush_stage == 'e':
                w, m, e = m, [], []
            else:
                w, m, e = [], [], []
            division_left = 0
        elif m_stall:
            w = []
        elif e_stall:
            w, m = m_surviving, []
        elif div_wait:
            w, m = m, []
        else:
            if m_redirect and not registered_control:
                killed = sum(r.counted_issue for r in m[len(m_surviving):] + e)
                w, m, e = m_surviving, [], []
                division_left = 0
            else:
                killed = sum(r.counted_issue for r in e[len(surviving):]) if redirect else 0
                w, m, e = m_surviving, surviving, entering_e
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
        tick += 1
    result = dict(cycles=cycles, instructions=2 * counters[1] + counters[2],
                  **{f'hpm{i}': counters[i] for i in range(1, 17)})
    if fusion:
        result['instructions'] = retired_instructions
    result.update(experimental)
    result['predictor_bits'] = predictor.direction.bits if predictor.direction else 2 * pht
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
    parser.add_argument('--lcb', choices=('same-cycle', 'registered'))
    parser.add_argument('--fusion', nargs='+', choices=FUSIONS, default=())
    parser.add_argument('--loop-cache', action='store_true')
    parser.add_argument('--early-address', type=int, choices=(1, 2), default=0)
    parser.add_argument('--direction-predictor', choices=('loop', 'tournament', 'tage'))
    parser.add_argument('--serial-alu', choices=('any', 'simple'))
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
                              gshare_pc_shift=args.gshare_pc_shift, lcb=args.lcb,
                              fusion=args.fusion, loop_cache=args.loop_cache,
                              early_address=args.early_address,
                              direction_predictor=args.direction_predictor,
                              serial_alu=args.serial_alu), indent=2))


if __name__ == '__main__':
    main()
