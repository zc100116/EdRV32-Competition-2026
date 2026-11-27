#!/usr/bin/env python3
"""M-8 native dots, draw-resident constants and statically scheduled context batches.
Host model of design section 10; FP32/SFU arithmetic reuses the M-5/M-6 corpus.
No RTL clock domain; issue/latency and resource costs are planning inputs.
"""
from collections import Counter
import math
import random

import m5_vertex as v
import m6_sfu as sfu


class NativeBuilder(v.Builder):
    def dot(self, a, b, n=3):
        return self.emit(f'DP{n}', a, b, mask='x')


def execute(program, inputs, fused=True):
    # Products of two FP32 numbers are exact in binary64. Integer alignment
    # and ties-to-even rounding below avoid binary64-to-FP32 double rounding.
    registers, outputs = {}, {}
    for ins in v.expanded(program):
        args = []
        for a in ins.args:
            values = [registers[a.reg]['xyzw'.index(c)] for c in a.swizzle]
            args.append([(-1 if a.negate else 1)*(abs(x) if a.absolute else x)
                         for x in values])
        op = ins.op
        if op.startswith('DP'):
            products = [a*b for a, b in zip(args[0][:int(op[-1])], args[1])]
            if fused:
                ratios = [p.as_integer_ratio() for p in products]
                exponent = max(d.bit_length()-1 for _, d in ratios)
                total = sum(n << (exponent-d.bit_length()+1) for n, d in ratios)
                discard = max(abs(total).bit_length()-24, exponent-149, 0)
                quotient, residue = divmod(abs(total), 1 << discard)
                halfway = 1 << discard
                quotient += 2*residue > halfway or (2*residue == halfway and quotient & 1)
                value = v.fp(math.ldexp((-1 if total < 0 else 1)*quotient, discard-exponent))
            else:
                products = [v.fp(p) for p in products] + [0.]*(4-len(products))
                value = v.fp(v.fp(products[0]+products[1])+v.fp(products[2]+products[3]))
            registers[ins.dst] = [value, 0., 0., 0.]
            continue
        # A one-instruction invocation retains exactly the M-5 masking semantics.
        loads = [v.Instruction('LOAD_ATTR', a.reg, key=a.reg) for a in ins.args]
        if op == 'STORE_VERTEX':
            outputs.update(v.execute(loads+[ins], registers))
        elif op != 'END':
            store = v.Instruction('STORE_VERTEX', args=(v.src(ins.dst),), key='out')
            if op == 'MOV' and len(ins.args) == 1:
                loads.append(v.Instruction('LOAD_ATTR', ins.dst, key=ins.dst))
            result = v.execute(loads+[ins, store], {**registers, **inputs})
            registers[ins.dst] = result['out']
    return outputs


def compile_state(state):
    old = v.Builder
    v.Builder = NativeBuilder
    result = v.compile_state(state)
    v.Builder = old
    return result


def duration(ins, lanes):
    if ins.op == 'LOAD_CONST':
        return 0, 0
    if ins.op in sfu.LATENCY:
        return 1, sfu.LATENCY[ins.op]+1
    if ins.op.startswith('DP'):
        beats = math.ceil(int(ins.op[-1])/lanes)
        return beats, beats+12
    beats = max(1, math.ceil(len(ins.mask)/lanes))
    delay = 11 if ins.op in ('MUL', 'FMA', 'ADD') else 2
    return beats, beats+delay


def schedule(code, lanes, contexts):
    """Static SSA list order, all contexts execute each instruction in that order.
    Direct two-port constant reads are prefetched one cycle with RF operands.
    No LOAD_CONST issue slots: constant registers refer to immutable draw banks.
    """
    constants = {i.dst for i in code if i.op == 'LOAD_CONST'}
    code = [i for i in code if i.op != 'LOAD_CONST']
    producers = {i.dst: k for k, i in enumerate(code) if i.dst}
    deps = [{producers[a.reg] for a in i.args if a.reg not in constants} for i in code]
    deps[-1] = set(range(len(code)-1))
    children = [[] for _ in code]
    for i, ds in enumerate(deps):
        for d in ds:
            children[d].append(i)
    critical = [0]*len(code)
    for i in reversed(range(len(code))):
        critical[i] = duration(code[i], lanes)[1]+max(
            (critical[j] for j in children[i]), default=0)
    todo, done, order, trace = set(range(len(code))), set(), [], []
    ready = [dict.fromkeys(constants, 0) for _ in range(contexts)]
    cycle = scalar_free = peak = 0
    live = set()
    writebacks = set()
    users = Counter(a.reg for i in code for a in i.args if a.reg not in constants)
    while todo:
        candidates = []
        for i in sorted(todo):
            if i >= min(todo)+16 or not deps[i] <= done:
                continue
            ins = code[i]
            consumed = Counter(a.reg for a in ins.args if a.reg not in constants)
            released = {reg for reg, count in consumed.items() if users[reg] == count}
            next_live = (live-released) | ({ins.dst} if ins.dst and users[ins.dst] else set())
            if len(next_live) > 32:
                continue
            now, sf, issued, returns = cycle, scalar_free, [], []
            reserved = set()
            beats, delay = duration(ins, lanes)
            for ctx in range(contexts):
                start = max(now, max((ready[ctx][a.reg] for a in ins.args), default=0),
                            sf if ins.op in sfu.LATENCY else 0)
                if ins.dst:
                    while start+delay in writebacks or start+delay in reserved:
                        start += 1
                    reserved.add(start+delay)
                if ins.op in sfu.LATENCY:
                    sf = start+4
                issued.append((start, ctx, i))
                returns.append(start+delay)
                now = start+beats
            # SFU's II4 spacing is intrinsic work, not a dependency bubble.
            busy = contexts*beats+(3*(contexts-1) if ins.op in sfu.LATENCY else 0)
            candidates.append(((now-cycle-busy, -critical[i], i),
                               i, now, sf, issued, returns, next_live, reserved))
        _, i, cycle, scalar_free, issued, returns, live, reserved = min(candidates)
        writebacks.update(reserved)
        peak = max(peak, len(live))
        users.subtract(a.reg for a in code[i].args if a.reg not in constants)
        for ctx in range(contexts):
            if code[i].dst:
                ready[ctx][code[i].dst] = returns[ctx]
        trace.extend(issued)
        order.append(i)
        todo.remove(i)
        done.add(i)
    # END waits for stores as well as arithmetic; store capture has two extra cycles.
    cycle += 2
    return dict(cycles=cycle/contexts, batch_cycles=cycle, contexts=contexts, lanes=lanes,
                order=order, trace=trace,
                listing=[dict(op=code[i].op, dst=code[i].dst, mask=code[i].mask,
                              key=code[i].key, args=[a.__dict__ for a in code[i].args])
                         for i in order],
                peak_regs=peak, constant_words=len(constants), dynamic_words=len(code),
                issue_lower_bound=sum(duration(i, lanes)[0] for i in code))


def study():
    states = dict(position=v.State(), D1=v.State(lights=1, texture=True),
                  D8=v.State(lights=8, texture=True),
                  G1=v.State(lights=1, generic=True, texture=True),
                  G8=v.State(lights=8, generic=True, texture=True))
    schedules = {}
    for name, state in states.items():
        code = compile_state(state)
        combinations = [(l, c) for l in (2, 4, 8) for c in (*range(1, 13), 16)]
        if name != 'D1':
            combinations = [(4, 12)]
        schedules[name] = {f'L{l}C{c}': schedule(code, l, c) for l, c in combinations}
    rng = random.Random(20261127)
    for name, state in states.items():
        code = compile_state(state)
        timing = schedules[name]['L4C12']
        dynamic = [i for i in code if i.op != 'LOAD_CONST']
        ordered = [i for i in code if i.op == 'LOAD_CONST']
        ordered += [dynamic[i] for i in timing['order']]
        for _ in range(16):
            inputs = v.random_inputs(rng)
            assert execute(code, inputs, False) == execute(ordered, inputs, False), name
    # Reuse the complete M-5 random/directed inputs and its independent reference.
    old_builder, old_execute, old_sfu = v.Builder, v.execute, v.sfu
    result = {}
    for fused in (False, True):
        v.Builder = NativeBuilder
        # execute() above invokes the unmodified interpreter for non-DP operations.
        def native(program, inputs):
            v.execute = old_execute
            value = execute(program, inputs, fused)
            v.execute = native
            return value
        v.execute, v.sfu = native, sfu.sfu
        measured = v.study()['variants']
        result['fused' if fused else 'staged'] = {
            name: {k: row[k] for k in ('errors', 'output_errors', 'peak_regs')}
            for name, row in measured.items()}
        v.execute = old_execute
    v.Builder, v.execute, v.sfu = old_builder, old_execute, old_sfu
    example = [v.Instruction('LOAD_ATTR', 'a', key='a'),
               v.Instruction('LOAD_ATTR', 'b', key='b'),
               v.Instruction('DP3', 'd', (v.src('a'), v.src('b')), mask='x'),
               v.Instruction('STORE_VERTEX', args=(v.src('d'),), key='out')]
    inputs = dict(a=[1+2**-23, 1., 0., 0.], b=[1-2**-23, -1., 0., 0.])
    directed = dict(exact=-2**-46, staged=execute(example, inputs, False)['out'][0],
                    fused=execute(example, inputs, True)['out'][0])
    return dict(schedules=schedules, precision=result, cancellation_example=directed)
