#!/usr/bin/env python3
"""Directed boundary crosses, residual boundaries, and deterministic random inputs."""
import random
from model import compute


def generate(path, width, count):
    p, eb = (24, 8) if width == 32 else (53, 11)
    f = p-1
    bias = (1 << (eb-1))-1
    inf = ((1 << eb)-1) << f
    sign = 1 << (width-1)
    one = bias << f
    edges = [0, 1, 2, (1 << f)-1, 1 << f, (1 << f)+1,
             one-1, one, one+1, one+(1 << (f-1)), one+(1 << f),
             inf-1, inf, inf+1, inf+(1 << (f-1)), inf+(1 << (f-1))+1]
    edges += [v | sign for v in edges[:]]
    rng = random.Random(0xF03+width)
    with path.open('w') as stream:
        def emit(a, b, op, rm):
            result, flags = compute(a, b, op, rm, width)
            stream.write(f'{a:x} {b:x} {op:x} {rm:x} {result:x} {flags:x}\n')
        for rm in range(5):
            for a in edges:
                emit(a, 0, 1, rm)
                for b in edges:
                    emit(a, b, 0, rm)
            # Adjacent representable squares and quotients exercise residual/tie decisions.
            for delta in range(-32, 33):
                emit(one+delta, one+1, 0, rm)
                emit(one+delta, 0, 1, rm)
        for i in range(count):
            a, b = rng.getrandbits(width), rng.getrandbits(width)
            if i % 4 == 0:
                a = rng.choice(edges)
            if i % 4 == 1:
                b = rng.choice(edges)
            emit(a, b, i % 2, i % 5)
