#!/usr/bin/env python3
# File: wide_model.py; Spec: cpu-spec 4.1-4.4; Clock: host.
# Explore ordered N-issue with v0.15 RAW/latency rules and explicit FU capacities.
# Width >2 assumes 128-bit I$ delivery and two parallel 8-byte predictor queries.
"""Hit-only architecture estimates, not a proposed RTL contract."""
from collections import deque

from analyze import CONTROL
from pipe_model import Predictor, Record, fetch_request


def fill_width(program, ib, halfwords, width):
    """F2 decodes width instructions into a two-group instruction buffer."""
    for _ in range(min(width, 2 * width - len(ib))):
        if not halfwords:
            break
        pc, meta = halfwords[0]
        inst = program[pc]
        length = inst.size // 2
        if len(halfwords) < length:
            break
        entry, taken, target, history, checkpoint = meta
        hit = bool(entry and entry[0].pc == pc)
        ib.append(Record(inst, hit, hit and taken, target,
                         ((pc >> 2) ^ history) & 4095, checkpoint))
        del halfwords[:length]


def request(predictor, pc, cross, width):
    return fetch_request(predictor, pc, cross, 8 if width == 2 else 16, width > 2)


def fits(instructions, width, alus, lsus, branches, restricted):
    """Allocate a program-order prefix; RAW never crosses lanes combinationally."""
    used = dict(alu=0, lsu=0, mul=0, div=0, branch=0)
    for pos, inst in enumerate(instructions):
        if pos and any(i.rd and i.rd in inst.sources for i in instructions[:pos]):
            return False
        if len(instructions) > 1 and inst.kind in {'csr', 'serial', 'illegal'}:
            return False
        unit = ('lsu' if inst.kind in {'load', 'store'} else
                'branch' if inst.kind in CONTROL else inst.kind)
        if unit in used:
            used[unit] += 1
    if used['alu'] > alus or used['lsu'] > lsus or used['branch'] > branches:
        return False
    if used['mul'] > 1 or used['div'] > 1:
        return False
    if restricted:
        # v0.15: one general lane, other lanes ALU/branch/JAL, with age swap.
        general = sum(i.kind not in {'alu', 'branch', 'jal'} for i in instructions)
        if general > 1:
            return False
    return len(instructions) <= width


def simulate(program, trace, begin, end, *, width=2, alus=2, lsus=1, branches=1,
             restricted=False, timeline=None):
    predictor = Predictor(128, 4096, 8, 4, 2)
    ib = deque()
    halfwords, pending = [], []
    fetch_pc, cross = trace[0], None
    e, m, w = [], [], []
    cursor = tick = cycles = instructions = division_left = 0
    active = False
    events = dict(mispredictions=0, raw_block=0, unit_block=0, operand_block=0)

    def event(name, record):
        if timeline is not None:
            timeline.append((tick, name, record.trace_index, record.instruction.pc))

    while True:
        if any(r.instruction.pc == end for r in w):
            break
        active |= any(r.instruction.pc == begin for r in w)
        if active:
            instructions += len(w)
        for record in w:
            event('commit', record)
        redirect = None
        surviving = []
        for record in e:
            surviving.append(record)
            inst = record.instruction
            taken = inst.kind in {'jal', 'jalr'} or (
                inst.kind == 'branch' and record.next_pc != inst.pc + inst.size)
            if not record.d_redirect and (record.taken != taken or (
                    record.taken and record.target != record.next_pc)):
                redirect = record
                break
        div_wait = bool(division_left and any(r.instruction.kind == 'div' for r in surviving))
        if div_wait:
            division_left -= 1
            redirect = None
        ready = {}
        for age, stage in ((2, m), (1, e)):
            for record in stage:
                inst = record.instruction
                if inst.rd:
                    ready[inst.rd] = max(0, {'load': 2, 'mul': 3, 'csr': 2}.get(
                        inst.kind, 1) - age)
        issued = []
        d_redirect = None
        if not redirect and not div_wait:
            for record in list(ib)[:width]:
                inst = record.instruction
                if cursor >= len(trace):
                    break
                if any(ready.get(s, 0) for s in inst.sources):
                    if active:
                        events['operand_block'] += 1
                    break
                if inst.kind == 'csr' and (e or m):
                    break
                candidates = [r.instruction for r in issued] + [inst]
                if not fits(candidates, width, alus, lsus, branches, restricted):
                    if active:
                        raw = any(i.rd and i.rd in inst.sources for i in candidates[:-1])
                        events['raw_block' if raw else 'unit_block'] += 1
                    break
                if inst.kind == 'jal' and not record.hit:
                    # An older unpredicted JAL monopolizes D, like v0.15.
                    d_redirect = record
                    record.d_redirect = True
                record.trace_index = cursor
                record.next_pc = trace[cursor + 1] if cursor + 1 < len(trace) else end + 4
                if inst.pc == trace[cursor]:
                    cursor += 1
                else:
                    # A taken older control may have a speculative younger in this group.
                    if not issued:
                        raise ValueError(f'trace mismatch {cursor}: {inst.pc:x}')
                    record.trace_index = -1
                    record.next_pc = inst.pc + inst.size
                issued.append(ib.popleft())
                event('issue', record)
                if inst.kind == 'div':
                    division_left = 33
                if d_redirect:
                    break
        flush = redirect or d_redirect
        query = None
        if not flush:
            halfwords.extend(pending)
            pending = []
            fill_width(program, ib, halfwords, width)
            if len(halfwords) <= (4 if width == 2 else 8):
                pending, fetch_pc, cross, query = request(predictor, fetch_pc, cross, width)
        if not div_wait:
            for record in surviving:
                predictor.update(record)
        if flush:
            predictor.restore(flush)
            fetch_pc, cross = flush.next_pc, None
            ib.clear()
            halfwords, pending = [], []
            cursor = flush.trace_index + 1
            if active:
                events['mispredictions'] += 1
            event('redirect', flush)
        elif query and query[1]:
            predictor.action(query[0][0])
        if div_wait:
            w, m = m, []
        else:
            w, m, e = m, surviving, issued
        if active:
            cycles += 1
        tick += 1
    return dict(cycles=cycles, instructions=instructions, ipc=instructions / cycles, **events)
