#!/usr/bin/env python3
# fpu_model.py — C2-F design evaluation, issue/scoreboard/WB cycle model.
# Design: docs/design/2026-11-27-cpu-v2-fpu.md. Clock: host, not RTL.
"""Hit-only trace replay; values/flags come from Spike, timings are estimates."""
from collections import Counter, deque
from dataclasses import dataclass
import re


SCHEMES = ('unified', 'bypass', 'split', 'wide', 'newton', 'parallel_d')
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
            # Seed + dependent internal extended-precision FMA sequence + exact residual.
            latency = (344 if d else 122) if n.startswith('fsqrt.') else (254 if d else 94)
            return latency, ('double' if d else 'core'), latency
        return (66 if d else 22), 'divide', (66 if d else 22)
    if n.startswith(('fadd.', 'fsub.', 'fmul.', *FUSED)):
        if scheme == 'wide':
            return 30, 'core', 1
        if d:
            return 30, 'double', (1 if scheme == 'parallel_d' else 4)
        if scheme == 'unified':
            return 14, 'core', 1
        if n.startswith(('fadd.', 'fsub.')):
            return 8, ('add' if scheme == 'split' else 'core'), 1
        return (10 if n.startswith('fmul.') else 14), 'core', 1
    if n.startswith('fcvt.'):
        return (8 if d else 6), 'convert', 1
    return 3, 'simple', 1


def simulate(program, trace, scheme='bypass', reads=2, queue_depth=16):
    """Slot0 all FP/LSU/control; slot1 independent integer ALU; ordered retirement."""
    ready = {}
    units = Counter()
    wb = set()
    integer_wb = [set(), set()]
    tails = set()
    pending = deque()
    predictor = [1] * 1024
    stats = Counter()
    cycle = index = 0
    fp_read_until = 0
    while index < len(trace) or pending:
        retired = 0
        fp_retired = False
        while pending and pending[0][0] <= cycle and retired < 2:
            if pending[0][1] and fp_retired:
                break
            fp_retired |= pending.popleft()[1]
            retired += 1
        if index == len(trace):
            cycle += 1
            continue
        if units['idiv'] > cycle:
            cycle += 1
            continue
        issued = []
        redirect = False
        blocked_tail = False
        for slot in range(2):
            if index == len(trace) or len(pending) == queue_depth:
                break
            ins = program[trace[index]]
            if slot and ins.kind != 'alu':
                break
            if any(ready.get(r, 0) > cycle for r in ins.sources):
                break
            if ins.rd and ready.get(ins.rd, 0) > cycle:
                break
            # Same-group RAW and WAW cannot use a just-issued result.
            if any(old.rd and (old.rd in ins.sources or old.rd == ins.rd) for old in issued):
                break
            if ins.kind == 'serial' and (pending or slot):
                break
            latency, unit, interval = timing(ins, scheme)
            fused = ins.name.startswith(FUSED)
            if ins.fp and fp_read_until > cycle:
                break
            if units[unit] > cycle:
                break
            latency += int(fused and reads == 2)
            done = cycle + latency
            # Variable-latency unified paths reserve the common four-stage tail.
            tail = (ins.kind == 'float' and unit == 'core'
                    and scheme in {'bypass', 'parallel_d', 'split', 'newton'})
            tail_start = done - 4
            if tail and tail_start in tails:
                blocked_tail = True
                break
            # Single FP RF write port; loads and compute arbitrate by issue age.
            if ins.rd and ins.rd.startswith('f'):
                while done in wb:
                    done += 1
                wb.add(done)
            elif ins.rd:
                while done in integer_wb[slot]:
                    done += 1
                integer_wb[slot].add(done)
            if ins.rd:
                ready[ins.rd] = done
            if tail:
                tails.add(tail_start)
            if unit != 'integer':
                units[unit] = cycle + interval
            if ins.fp:
                fp_read_until = cycle + (2 if fused and reads == 2 else 1)
            pending.append((done, bool(ins.rd and ins.rd.startswith('f'))))
            issued.append(ins)
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
            events = [done for done, _ in pending if done > cycle]
            if blocked_tail:
                events.append(cycle + 1)
            events += [value for value in units.values() if value > cycle]
            if fp_read_until > cycle:
                events.append(fp_read_until)
            cycle = (min(events) if events and not (pending and pending[0][0] <= cycle)
                     else cycle + 1)
        else:
            cycle += 3 if redirect else 1
    return dict(cycles=cycle, **stats)


def selftest():
    """Directed timing contracts: RAW, separate register names, FMA reads, long ops."""
    p = {0: decode(0, 'fadd.s', 'f1,f2,f3'), 4: decode(4, 'fadd.s', 'f4,f1,f3')}
    assert simulate(p, [0, 4])['cycles'] == 17
    p[4] = decode(4, 'addi', 'x1,x0,1')
    assert simulate(p, [0, 4])['cycles'] == 9
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
    assert simulate(p, list(p))['cycles'] == 20
    p = {0: decode(0, 'lw', 'x1,0(x0)'), 4: decode(4, 'addi', 'x2,x0,1'),
         8: decode(8, 'addi', 'x3,x0,1'), 12: decode(12, 'addi', 'x4,x3,1')}
    assert simulate(p, list(p))['cycles'] == 5
    print('PASS: RAW, namespaces, FMA reads, FDIV overlap, FLD beats, dual ALU, FP/int WB')


if __name__ == '__main__':
    selftest()
