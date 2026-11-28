#!/usr/bin/env python3
"""D exact rational directed and seeded randomized arithmetic vectors."""
import itertools
import random
from model import fma
VALUES = [0, 1 << 63, 1, (1 << 63)|1, 0xfffffffffffff, 0x10000000000000,
          0x3ff0000000000000, 0xbff0000000000000, 0x3ff0000000000001,
          0x7fefffffffffffff, 0xffefffffffffffff, 0x7ff0000000000000,
          0xfff0000000000000, 0x7ff8000000000001, 0xfff8abcdef123456,
          0x7ff0000000000001]
INSTR = [0x2000043, 0x2000047, 0x200004b, 0x200004f, 0x2000053, 0xa000053, 0x12000053]
def arithmetic(op,a,b,c,rm):
    if op < 4: return fma(a,b,c,op,rm)
    if op < 6: return fma(a,0x3ff0000000000000,b,op-4,rm)
    return fma(a,b,(a^b)&(1<<63),0,rm)
def generate(path,tier):
    rng=random.Random(0xf0464)
    with path.open('w') as stream:
        def emit(op,a,b,c,rm):
            result,flags=arithmetic(op,a,b,c,rm)
            stream.write(f'{INSTR[op]:08x} {a:016x} {b:016x} {c:016x} 0 {rm:x} '
                         f'{result:016x} {flags:02x} 0\n')
        for op in range(7): emit(op,0x3ff0000000000001,0x3feffffffffffffe,0xbff0000000000000,0)
        for a,b,op,rm in itertools.product(VALUES,VALUES,range(7),range(5)):
            emit(op,a,b,VALUES[(a^b)%len(VALUES)],rm)
        # Exact cancellation and near-halfway single-rounding cases across the exponent range.
        for exp in (1,2,10,512,1022,1023,1024,1536,2045,2046):
            for rm,op in itertools.product(range(5),range(4)):
                emit(op,(exp<<52)|1,0x3feffffffffffffe,(exp<<52)|(1<<63),rm)
        for _ in range(10000 if tier=='smoke' else 1000000):
            a,b,c=(rng.getrandbits(64) for _ in range(3))
            if rng.randrange(4)==0:
                a=rng.choice(VALUES); b=rng.choice(VALUES); c=rng.choice(VALUES)
            emit(rng.randrange(7),a,b,c,rng.randrange(5))
