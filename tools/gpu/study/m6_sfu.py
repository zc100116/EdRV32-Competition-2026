#!/usr/bin/env python3
"""M-6 host small-table FP32 SFU precision and modulo reservation model.
Tables are constructed by host libm; per-sample evaluation uses FP32 arithmetic.
No clock domain. II=4 is a reservation proof, not a physical timing result.
"""
import math
import random

import m5_vertex as v

LATENCY = dict(RCP=46, RSQ=67, LOG2=87, EXP2=77)
RCP = tuple(v.fp(1/(1+(i+.5)/64)) for i in range(64))
RSQ = tuple(v.fp(1/math.sqrt(1+3*(i+.5)/64)) for i in range(64))
LOG = tuple(v.fp(math.log2(.75+i/64)) for i in range(49))
INV = tuple(v.fp(1/(.75+i/64)) for i in range(49))
EXP = tuple(v.fp(2**(i/64)) for i in range(64))


def sfu(op, x, rsq_iterations=2):
    if op == 'RCP':
        if x == 0:
            return math.copysign(math.inf, x)
        m, e = math.frexp(abs(x))
        m, e = m*2, e-1
        y = RCP[int((m-1)*64)]
        for _ in range(2):
            y = v.fma(y, v.fma(-m, y, 1.), y)
        return v.fp(math.copysign(math.ldexp(y, -e), x))
    if op == 'RSQ':
        if x == 0:
            return math.inf
        m, e = math.frexp(x)
        m, e = m*2, e-1
        if e & 1:
            m, e = m*2, e-1
        y = RSQ[int((m-1)*64/3)]
        for _ in range(rsq_iterations):
            y = v.fp(y*v.fma(-.5*m, v.fp(y*y), 1.5))
        return v.fp(math.ldexp(y, -e//2))
    if op == 'LOG2':
        if x == 0:
            return -math.inf
        m, e = math.frexp(x)
        if m < .75:
            m, e = m*2, e-1
        i = round((m-.75)*64)
        r = v.fp(v.fp(m-(.75+i/64))*INV[i])
        p = v.fp(1/5)
        for c in (-1/4, 1/3, -.5, 1.):
            p = v.fma(r, p, v.fp(c))
        return v.fma(v.fp(r*p), v.fp(1/math.log(2)), v.fp(e+LOG[i]))
    if op == 'EXP2':
        if x == -math.inf:
            return 0.
        e = math.floor(x)
        i = int((x-e)*64)
        r = v.fp((x-e-i/64)*v.fp(math.log(2)))
        p = v.fp(1/120)
        for c in (1/24, 1/6, .5, 1., 1.):
            p = v.fma(r, p, v.fp(c))
        return v.fp(math.ldexp(v.fp(EXP[i]*p), e))
    raise ValueError(op)


def reservation():
    # Every request uses a prefix of these eight arithmetic slots. Slots 0..7
    # have unique (engine, phase mod 4), so arbitrary opcode mixtures cannot clash.
    slots = [(4, 0), (14, 0), (24, 1), (34, 1),
             (45, 0), (55, 0), (65, 1), (75, 1)]
    assert len({(engine, offset % 4) for offset, engine in slots}) == 8
    counts = dict(RCP=4, RSQ=6, LOG2=8, EXP2=7)
    occupied = set()
    rng = random.Random(20261127)
    for request in range(512):
        op = rng.choice(list(counts))
        for offset, engine in slots[:counts[op]]:
            key = (request*4+offset, engine)
            assert key not in occupied
            occupied.add(key)
    return dict(slots=slots, counts=counts, requests=512, engines=2, ii=4,
                max_latency=87)


def study():
    rng = random.Random(20261127)
    result = {}
    for op in LATENCY:
        pairs = []
        for _ in range(20000):
            x = v.fp(rng.uniform(-100, 32) if op == 'EXP2' else 2**rng.uniform(-32, 32))
            target = dict(RCP=lambda: 1/x, RSQ=lambda: 1/math.sqrt(x),
                          LOG2=lambda: math.log2(x), EXP2=lambda: 2**x)[op]()
            pairs.append((sfu(op, x), target))
        if op == 'LOG2':
            for j in range(1, 128):
                for x in (v.fp(1+j*2**-23), v.fp(1-j*2**-24)):
                    pairs.append((sfu(op, x), math.log2(x)))
        result[op] = v.error_summary(pairs)
    for name, span in (('pow_narrow', .8), ('pow_broad', 8)):
        rows = {n: [] for n in ('m5', 'small')}
        worst, underflow = {}, 0
        for _ in range(20000):
            x, y = v.fp(2**rng.uniform(-span, 0)), v.fp(rng.uniform(.25, 127.75))
            target = x**y
            if target < 2**-126:
                underflow += 1
                continue
            for n, fn in (('m5', v.sfu), ('small', sfu)):
                log = fn('LOG2', x)
                product = v.fp(log*y)
                actual = fn('EXP2', product)
                rows[n].append((actual, target))
                rel = abs(actual-target)/target
                if rel > worst.get(n, {}).get('relative', -1):
                    worst[n] = dict(x=x, y=y, relative=rel, log=log, product=product,
                                    log_absolute_error=abs(log-math.log2(x)),
                                    multiply_absolute_error=abs(product-log*y))
        result[name] = dict(errors={n: v.error_summary(p) for n, p in rows.items()},
                            worst=worst, underflow_count=underflow)
    return dict(errors=result, table_bits=32*sum(map(len, (RCP, RSQ, LOG, INV, EXP))),
                reservation=reservation(), latencies=LATENCY,
                resources=[3284, 1864, 4, 1, 512])
