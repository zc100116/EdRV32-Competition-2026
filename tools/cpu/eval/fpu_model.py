#!/usr/bin/env python3
# fpu_model.py — C2-F design evaluation, issue/scoreboard/WB cycle model.
# Design: docs/design/2026-11-27-cpu-v2-fpu.md. Clock: host, not RTL.
"""Hit-only trace replay; values/flags come from Spike, timings are estimates."""
from collections import Counter, deque
from dataclasses import dataclass
import re

from fpu_timing import latency as stage_latency


SCHEMES = ('unified', 'bypass', 'split', 'wide', 'newton', 'parallel_d', 'serial_d')
REG = re.compile(r'\b[xf]\d+\b')
BRANCHES = {'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'}
LOADS = {'lb', 'lbu', 'lh', 'lhu', 'lw', 'flw', 'fld'}
STORES = {'sb', 'sh', 'sw', 'fsw', 'fsd'}
FUSED = ('fmadd.', 'fmsub.', 'fnmadd.', 'fnmsub.')


@dataclass(frozen=True)
class Instruction:
    pc: int
    name: str
    rd: str | None
    sources: tuple
    kind: str
    fp: bool
    double: bool


def decode(pc, name, operands):
    regs = tuple(REG.findall(operands.split('#')[0]))
    kind = 'alu'
    if name in BRANCHES:
        kind = 'branch'
    elif name in {'jal', 'jalr'}:
        kind = 'jump'
    elif name in LOADS:
        kind = 'load'
    elif name in STORES:
        kind = 'store'
    elif name.startswith(('csr', 'fence')) or name in {'ecall', 'ebreak', 'mret'}:
        kind = 'serial'
    elif name.startswith('f'):
        kind = 'float'
    elif name in {'mul', 'mulh', 'mulhu', 'mulhsu'}:
        kind = 'mul'
    elif name in {'div', 'divu', 'rem', 'remu'}:
        kind = 'div'
    writes = kind not in {'branch', 'store'}
    rd = regs[0] if writes and regs else None
    sources = regs[1:] if writes and regs else regs
    return Instruction(pc, name, None if rd == 'x0' else rd,
                       tuple(r for r in sources if r != 'x0'), kind,
                       name.startswith('f') and not name.startswith('fence'),
                       '.d' in name or name in {'fld', 'fsd'})


def timing(ins, scheme):
    """Return result latency, unit, initiation interval; two-read FMA added below."""
    n, d = ins.name, ins.double
    if ins.kind in {'load', 'store'}:
        return (3 if d else 2), 'lsu', (2 if d else 1)
    if ins.kind == 'mul':
        return 4, 'imul', 1
    if ins.kind == 'div':
        return 34, 'idiv', 34
    if ins.kind != 'float':
        return (2 if ins.kind == 'serial' else 1), 'integer', 1
    if n.startswith(('fdiv.', 'fsqrt.')):
        if scheme == 'newton':
            # p+3 internal precision: four S APMs, twelve D APMs.
            internal = 21 if d else 11
            count = (11 if d else 8) if n.startswith('fsqrt.') else (8 if d else 6)
            value = count * internal + (7 if d else 5)
            return value, ('double' if d else 'core'), value
        value = stage_latency(('D' if d else 'S') + ' DIV/SQRT')
        return value, 'divide', value
    if n.startswith(('fadd.', 'fsub.', 'fmul.', *FUSED)):
        if d and scheme == 'serial_d':
            # Twelve dependent single-APM terms, each with three registered phases.
            return 45, 'core', 36
        if scheme == 'wide':
            return stage_latency('D FMA'), 'core', 1
        prefix = 'D' if d else 'S'
        operation = ('ADD' if n.startswith(('fadd.', 'fsub.')) else
                     'MUL' if n.startswith('fmul.') else 'FMA')
        if scheme == 'unified':
            operation = 'FMA'
        value = stage_latency(prefix + ' ' + operation)
        unit = 'double' if d else ('add' if scheme == 'split' and operation == 'ADD'
                                  else 'core')
        return value, unit, (4 if d and scheme != 'parallel_d' else 1)
    if n.startswith('fcvt.'):
        return stage_latency(('D' if d else 'S') + ' convert'), 'convert', 1
    if n.startswith(('fsgnj', 'fmv.')):
        return 1, 'simple', 1
    return 2, 'simple', 1


def simulate(program, trace, scheme='bypass', reads=2, queue_depth=8, queue_forward=True):
    """Slot0 all FP/LSU/control; slot1 independent integer ALU; ordered retirement."""
    ready = {}
    latest = {}
    committed = {}
    units = Counter()
    wb = set()
    integer_wb = [set(), set()]
    tails = set()
    # Integer-only four-entry FF records have independent writes; migrated RAM
    # queues have two interleaved single-write banks.
    banks = [set() for _ in range(4 if queue_depth == 4 else 2)]
    written = {}
    fp_destination = {}
    double_result = {}
    arithmetic_result = {}
    lsu_double_until = 0
    decomposition = Counter()
    pending = deque()
    predictor = [1] * 1024
    stats = Counter()
    cycle = index = 0
    fp_read_until = 0
    while index < len(trace) or pending:
        reason = 'integer'
        retired = 0
        fp_retired = False
        while pending and pending[0][0] <= cycle and retired < 2:
            if pending[0][1] and fp_retired:
                break
            entry = pending.popleft()
            fp_retired |= entry[1]
            if entry[5]:
                committed[entry[5]] = entry[6]
            retired += 1
        if index == len(trace):
            if pending:
                head = pending[0]
                reason = ('fd_beat' if head[4] and cycle == head[2] - 1 else
                          'writeback' if head[2] <= cycle < head[0] else
                          'dependency' if head[3] else 'integer')
            decomposition[reason] += 1
            cycle += 1
            continue
        if units['idiv'] > cycle:
            decomposition['integer'] += 1
            cycle += 1
            continue
        issued = []
        redirect = False
        blocked_tail = False
        blocked = []
        for slot in range(2):
            if index == len(trace):
                break
            if len(pending) == queue_depth:
                reason = 'structure' if any(item[3] for item in pending) else 'integer'
                break
            ins = program[trace[index]]
            if slot and ins.kind != 'alu':
                break
            blocked = [r for r in (*ins.sources, ins.rd) if r and ready.get(r, 0) > cycle]
            if not queue_forward:
                blocked += [r for r in ins.sources if r.startswith('f')
                            and ready.get(r, 0) <= cycle
                            and latest.get(r) != committed.get(r)
                            and not (ready.get(r) == cycle and arithmetic_result.get(r))
                            and latest.get(r) != pending[0][6]]
            if blocked:
                reason = ('fd_beat' if any(double_result.get(r) and
                                          written[r] - 1 == cycle for r in blocked)
                          else 'writeback' if any(written.get(r, 0) <= cycle for r in blocked)
                          else 'dependency' if ins.fp or any(fp_destination.get(r)
                                                            for r in blocked)
                          else 'integer')
                break
            # Same-group RAW and WAW cannot use a just-issued result.
            if any(old.rd and (old.rd in ins.sources or old.rd == ins.rd) for old in issued):
                break
            if ins.kind == 'serial' and (pending or slot):
                reason = 'structure' if any(item[3] for item in pending) else 'integer'
                break
            latency, unit, interval = timing(ins, scheme)
            fused = ins.name.startswith(FUSED)
            if ins.fp and fp_read_until > cycle:
                reason = 'structure'
                break
            if units[unit] > cycle:
                reason = ('fd_beat' if unit == 'lsu' and lsu_double_until > cycle
                          else 'structure' if ins.fp else 'integer')
                break
            latency += int(fused and reads == 2)
            done = cycle + latency
            # Variable-latency unified paths reserve the common two-stage S / three-stage D tail.
            tail = (ins.kind == 'float' and unit in {'core', 'double'}
                    and scheme in {'bypass', 'parallel_d', 'split', 'newton'})
            tail_start = done - (3 if ins.double else 2)
            tail_key = (ins.double, tail_start)
            if tail and tail_key in tails:
                reason = 'structure'
                blocked_tail = True
                break
            raw_done = done
            bank = stats['instructions'] % len(banks)
            # One FP completion write and one write per striped data bank.
            # Older instructions reserve first; younger results remain in source latches.
            if ins.rd and ins.rd.startswith('f'):
                while done in wb or done in banks[bank]:
                    done += 1
                wb.add(done)
            elif ins.rd:
                while done in integer_wb[slot] or done in banks[bank]:
                    done += 1
                integer_wb[slot].add(done)
            else:
                # PC is also completion data for branches/stores without a destination.
                while done in banks[bank]:
                    done += 1
            banks[bank].add(done)
            if ins.rd:
                ready[ins.rd] = done
                latest[ins.rd] = stats['instructions']
                written[ins.rd] = raw_done
                fp_destination[ins.rd] = ins.fp
                double_result[ins.rd] = ins.double and ins.kind == 'load'
                arithmetic_result[ins.rd] = ins.kind == 'float'
            if tail:
                tails.add(tail_key)
            if unit != 'integer':
                units[unit] = cycle + interval
            if unit == 'lsu' and ins.double:
                lsu_double_until = cycle + 2
            if ins.fp:
                fp_read_until = cycle + (2 if fused and reads == 2 else 1)
            pending.append((done, bool(ins.rd and ins.rd.startswith('f')), raw_done, ins.fp,
                            ins.double and ins.kind == 'load', ins.rd,
                            stats['instructions']))
            issued.append(ins)
            if stats['instructions'] % 256 == 0:
                # Keep only live port reservations; elapsed cycles no longer occupy hardware.
                wb.intersection_update(value for value in tuple(wb) if value >= cycle)
                tails.intersection_update(value for value in tuple(tails) if value[1] >= cycle)
                for reservations in (*banks, *integer_wb):
                    reservations.intersection_update(value for value in tuple(reservations)
                                                      if value >= cycle)
            stats['instructions'] += 1
            stats['fp_instructions'] += ins.fp
            index += 1
            if ins.kind in {'branch', 'jump'}:
                next_pc = trace[index] if index < len(trace) else ins.pc + 4
                taken = next_pc != ins.pc + 4
                if ins.kind == 'branch':
                    pi = (ins.pc >> 2) & 1023
                    redirect = (predictor[pi] >= 2) != taken
                    predictor[pi] = min(3, predictor[pi] + 1) if taken else max(0, predictor[pi]-1)
                else:
                    redirect = ins.name == 'jalr'
                stats['redirects'] += redirect
                break
            if ins.kind == 'serial':
                break
        if not issued:
            events = [value for item in pending for value in (item[0], item[2])
                      if value > cycle]
            events += [written[r] - 1 for r in blocked
                       if double_result.get(r) and written[r] - 1 > cycle]
            if lsu_double_until > cycle:
                events.append(lsu_double_until)
            if blocked_tail:
                events.append(cycle + 1)
            events += [value for value in units.values() if value > cycle]
            if fp_read_until > cycle:
                events.append(fp_read_until)
            next_cycle = (min(events) if events and not (pending and pending[0][0] <= cycle)
                          else cycle + 1)
            # Count mutually exclusive elapsed cycles, not independent worst-case penalties.
            decomposition[reason] += next_cycle - cycle
            cycle = next_cycle
        else:
            elapsed = 3 if redirect else 1
            decomposition['integer'] += elapsed
            cycle += elapsed
    return dict(cycles=cycle, components=dict(decomposition), **stats)


def selftest():
    """Directed timing contracts: RAW, separate register names, FMA reads, long ops."""
    p = {0: decode(0, 'fadd.s', 'f1,f2,f3'), 4: decode(4, 'fadd.s', 'f4,f1,f3')}
    assert simulate(p, [0, 4])['cycles'] == 11
    p[4] = decode(4, 'addi', 'x1,x0,1')
    assert simulate(p, [0, 4])['cycles'] == 6
    p[0] = decode(0, 'fmadd.s', 'f1,f2,f3,f4')
    assert simulate(p, [0], reads=2)['cycles'] == simulate(p, [0], reads=3)['cycles'] + 1
    p[0] = decode(0, 'fdiv.s', 'f1,f2,f3')
    assert simulate(p, [0, 4])['cycles'] == simulate(p, [0])['cycles']
    assert timing(decode(0, 'fld', 'f1,0(x2)'), 'bypass') == (3, 'lsu', 2)
    p = {0: decode(0, 'addi', 'x1,x0,1'), 4: decode(4, 'addi', 'x2,x0,2')}
    assert simulate(p, [0, 4])['cycles'] == 2
    p = {0: decode(0, 'fmadd.s', 'f1,f2,f3,f4')}
    for i in range(1, 8):
        p[4*i] = decode(4*i, 'addi', 'x1,x1,1')
    p[32] = decode(32, 'fadd.s', 'f5,f6,f7')
    assert simulate(p, list(p))['cycles'] == 15
    p = {0: decode(0, 'lw', 'x1,0(x0)'), 4: decode(4, 'addi', 'x2,x0,1'),
         8: decode(8, 'addi', 'x3,x0,1'), 12: decode(12, 'addi', 'x4,x3,1')}
    assert simulate(p, list(p))['cycles'] == 5
    p = {0: decode(0, 'lw', 'x1,0(x2)'), 4: decode(4, 'addi', 'x3,x0,1'),
         8: decode(8, 'bne', 'x4,x5,8')}
    assert simulate(p, list(p))['cycles'] == 4  # branch PC and load share bank0
    assert simulate(p, list(p))['components']['writeback'] == 1
    assert simulate(p, list(p), queue_depth=4)['components'].get('writeback', 0) == 0
    p = {0: decode(0, 'fdiv.s', 'f1,f2,f3')}
    for i in range(1, 17):
        p[4*i] = decode(4*i, 'addi', f'x{i},x0,1')
    p[68] = decode(68, 'fmadd.s', 'f8,f9,f10,f11')
    small = simulate(p, list(p), queue_depth=8)
    large = simulate(p, list(p), queue_depth=16)
    assert small['cycles'] > large['cycles']
    for result in (small, large):
        assert result['cycles'] == sum(result['components'].values())
    p = {0: decode(0, 'fcvt.s.w', 'f1,x1'),
         4: decode(4, 'flw', 'f2,0(x2)'),
         8: decode(8, 'fsgnj.s', 'f3,f2,f2')}
    collision = simulate(p, list(p))
    assert collision['cycles'] == 6
    assert collision['components']['writeback'] == 1
    p = {0: decode(0, 'fld', 'f1,0(x2)'),
         4: decode(4, 'fadd.d', 'f2,f1,f3')}
    assert simulate(p, list(p))['components']['fd_beat'] == 1
    p = {0: decode(0, 'fdiv.s', 'f1,f2,f3'),
         4: decode(4, 'fcvt.s.w', 'f4,x2')}
    for i in range(2, 6):
        p[4*i] = decode(4*i, 'addi', 'x1,x1,1')
    p[24] = decode(24, 'fmadd.s', 'f5,f4,f6,f7')
    assert simulate(p, list(p))['cycles'] == 23
    assert simulate(p, list(p), queue_forward=False)['cycles'] == 29
    p = {0: decode(0, 'fdiv.s', 'f1,f2,f3'),
         4: decode(4, 'flw', 'f4,0(x2)'),
         8: decode(8, 'fmadd.s', 'f5,f4,f6,f7')}
    assert simulate(p, list(p))['cycles'] == 22
    assert simulate(p, list(p), queue_forward=False)['cycles'] == 29
    print('PASS: 8/16 queue, disjoint accounting, RAW, namespaces, FMA reads, '
          'FDIV overlap, FLD beats, dual ALU, FP/int WB, head-only forwarding')


if __name__ == '__main__':
    selftest()
