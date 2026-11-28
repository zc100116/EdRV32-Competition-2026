#!/usr/bin/env python3
"""M-6 host static list scheduling and executable relative-constant lamp loops.
Four contexts share one instruction order; no hardware out-of-order issue.
Latency and storage results are models, not FPGA implementation measurements.
"""
from collections import Counter
from dataclasses import replace
import math
import random
import re

import m5_vertex as v


def list_schedule(code, width, latency=10):
    producer = {ins.dst: i for i, ins in enumerate(code) if ins.dst}
    deps = [{producer[a.reg] for a in ins.args} for ins in code]
    # All externally visible stores precede END. No general memory side effects.
    deps[-1] |= set(range(len(code)-1))
    users = Counter(a.reg for ins in code for a in ins.args)
    critical = [0]*len(code)
    children = [[] for _ in code]
    for i, ds in enumerate(deps):
        for d in ds:
            children[d].append(i)
    for i in range(len(code)-1, -1, -1):
        delay = v.SFU_LATENCY.get(code[i].op, latency+4)
        critical[i] = delay+max((critical[j] for j in children[i]), default=0)
    todo, done, live, order = set(range(len(code))), set(), set(), []
    ready, cycle, scalar_free = [{} for _ in range(4)], 0, 0
    while todo:
        candidates = []
        oldest = min(todo)
        for i in sorted(todo):
            if i >= oldest+16 or not deps[i] <= done:
                continue
            ins = code[i]
            released = {a.reg for a in ins.args
                        if users[a.reg] == sum(b.reg == a.reg for b in ins.args)}
            next_live = (live-released) | ({ins.dst} if ins.dst and users[ins.dst] else set())
            if len(next_live) > 32:
                continue
            now, sf = cycle, scalar_free
            returns = []
            for ctx in range(4):
                available = max((ready[ctx][a.reg] for a in ins.args), default=0)
                start = max(now, available, sf if ins.op in v.SFU_LATENCY else 0)
                beats = math.ceil(len(ins.mask)/width) if ins.op != 'END' else 1
                if ins.op in v.SFU_LATENCY:
                    beats, delay = 1, v.SFU_LATENCY[ins.op]
                    sf = start+4
                elif ins.op in ('LOAD_ATTR', 'LOAD_CONST', 'MOV', 'MIN', 'MAX',
                                'CMP', 'SELECT'):
                    delay = beats+1
                else:
                    delay = beats+latency
                returns.append(start+delay)
                now = start+beats
            busy = 4*(1 if ins.op in v.SFU_LATENCY else
                      math.ceil(len(ins.mask)/width) if ins.op != 'END' else 1)
            candidates.append(((now-cycle-busy, -critical[i], len(next_live), i),
                               i, now, sf, returns, next_live))
        _, i, cycle, scalar_free, returns, live = min(candidates)
        ins = code[i]
        for a in ins.args:
            users[a.reg] -= 1
        if ins.dst:
            for ctx in range(4):
                ready[ctx][ins.dst] = returns[ctx]
        order.append(ins)
        todo.remove(i)
        done.add(i)
    physical, peak = v.allocate(order)
    scheduled = v.schedule(order, width, latency)
    last_end, max_wait = 0, 0
    for start, _, pc in scheduled['trace']:
        ins = order[pc]
        beats = 1 if ins.op in v.SFU_LATENCY or ins.op == 'END' else math.ceil(
            len(ins.mask)/width)
        max_wait = max(max_wait, start-last_end)
        last_end = start+beats
    return order, physical, dict(**scheduled, peak_regs=peak, max_wait=max_wait,
                                order=[code.index(ins) for ins in order])


def lamp_loop(code, state):
    """Collapse each side's light bodies, retaining one carried color register.
    LOAD_CONST_REL uses l<loop index>_<field>, with stride equal to lamp record size.
    """
    result, cursor = [], 0
    field = 'position' if state.generic else 'direction'
    for _ in range(2 if state.two_side else 1):
        starts = [i for i in range(cursor, len(code))
                  if re.fullmatch(r'l\d+_'+field, code[i].key)][:state.lights]
        start = starts[0]
        # The last ADD/FMA before the post-light MAX is the color recurrence.
        end = starts[-1]
        for j in range(end, len(code)):
            if (code[j].op == 'MAX' and j > end and code[j-1].op ==
                    ('ADD' if state.generic else 'FMA') and code[j].mask == 'xyzw'):
                end = j
                break
        body = code[start:starts[1]] if state.lights > 1 else code[start:end]
        carry = body[-1].args[0 if state.generic else 2].reg
        body = [replace(ins, op='LOAD_CONST_REL', key=ins.key[3:])
                if ins.op == 'LOAD_CONST' and ins.key.startswith('l0_') else ins
                for ins in body]
        body[-1] = replace(body[-1], dst=carry)
        # Following instructions refer to the final unrolled accumulation.
        final = code[end-1].dst
        code = [replace(ins, args=tuple(replace(a, reg=carry) if a.reg == final else a
                                       for a in ins.args)) for ins in code]
        result.extend(code[cursor:start])
        result.append(v.Instruction('LOOP', count=state.lights, body=tuple(body)))
        cursor = end
    result.extend(code[cursor:])
    return result


def expand_relative(code):
    result = []
    for ins in code:
        if ins.op == 'LOOP':
            for light in range(ins.count):
                result.extend(replace(b, op='LOAD_CONST', key=f'l{light}_'+b.key)
                              if b.op == 'LOAD_CONST_REL' else b for b in ins.body)
        else:
            result.append(ins)
    return result


def loop_words(code):
    return sum(2+len(i.body) if i.op == 'LOOP' else 1 for i in code)


def study():
    result, loops = {}, {}
    rng = random.Random(20261127)
    for name, state in v.VARIANTS.items():
        original = v.compile_state(state)
        row = {}
        inputs = [v.random_inputs(rng) for _ in range(16)]
        for width in (1, 2, 4):
            order, physical, timing = list_schedule(original, width)
            for u in inputs:
                expected = v.execute(original, u)
                assert v.execute(order, u) == expected, (name, width, 'SSA')
                assert v.execute(physical, u) == expected, (name, width, 'physical')
            timing['old_cycles'] = v.schedule(original, width, 10)['cycles']
            row[f'W{width}'] = timing
        result[name] = row
        if state.lights == 8:
            loop = lamp_loop(original, state)
            expanded = expand_relative(loop)
            for u in inputs:
                assert v.execute(expanded, u) == v.execute(original, u), name
            loops[name] = dict(unrolled_words=len(original), loop_words=loop_words(loop),
                               dynamic_words=len(expanded),
                               original_cycles_W2=v.schedule(original, 2, 10)['cycles'],
                               loop_cycles_W2=v.schedule(expanded, 2, 10)['cycles'] +
                               2*state.lights*(2 if state.two_side else 1),
                               body_words=[len(i.body) for i in loop if i.op == 'LOOP'])
    return dict(variants=result, loops=loops, execution_samples_per_variant=16)
