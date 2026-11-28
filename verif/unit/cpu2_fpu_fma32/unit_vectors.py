#!/usr/bin/env python3
"""Exact arithmetic and bit-encoding references for the S arithmetic units."""
import itertools
import random
from fractions import Fraction
from model import finite, fma
from vectors import directed, random_cases

VALUES = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x807fffff,
          0x00800000, 0x80800000, 0x3f800000, 0xbf800000, 0x3f800001,
          0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000,
          0x7fc00001, 0xffcabcde, 0x7f800001, 0xff812345]


def arithmetic(op, a, b, c, rm):
    if op < 4:
        return fma(a, b, c, op, rm)
    if op == 4 or op == 5:
        return fma(a, 0x3f800000, b, op - 4, rm)
    return fma(a, b, (a ^ b) & 0x80000000, 0, rm)


def arithmetic_instr(op):
    return [0x43, 0x47, 0x4b, 0x4f, 0x53, 0x08000053, 0x10000053][op]


def nan(x):
    return x & 0x7f800000 == 0x7f800000 and bool(x & 0x7fffff)


def snan(x):
    return nan(x) and not x & 0x400000


def short(op, a, b):
    if op < 3:
        sign = [b >> 31, 1 ^ (b >> 31), (a ^ b) >> 31][op]
        return (a & 0x7fffffff) | (sign << 31), 0, 0
    if op < 5:
        flags = 16 * (snan(a) or snan(b))
        if nan(a) and nan(b):
            return 0x7fc00000, flags, 0
        if nan(a) or nan(b):
            return b if nan(a) else a, flags, 0
        # Signed-magnitude ordering also handles infinities without host floats.
        key = lambda x: (~x & 0xffffffff) if x >> 31 else x | 0x80000000
        return (min if op == 3 else max)((a, b), key=key), flags, 0
    if op < 8:
        flags = 16 * ((snan(a) or snan(b)) if op == 5 else (nan(a) or nan(b)))
        if nan(a) or nan(b):
            return 0, flags, 1
        zero_equal = not ((a | b) & 0x7fffffff)
        key = lambda x: (~x & 0xffffffff) if x >> 31 else x | 0x80000000
        equal = a == b or zero_equal
        less = not zero_equal and key(a) < key(b)
        return int([equal, less, less or equal][op-5]), flags, 1
    exponent, fraction, sign = (a >> 23) & 255, a & 0x7fffff, a >> 31
    if exponent == 255:
        index = (9 if fraction & 0x400000 else 8) if fraction else (0 if sign else 7)
    elif exponent == 0:
        index = (2 if sign else 5) if fraction else (3 if sign else 4)
    else:
        index = 1 if sign else 6
    return 1 << index, 0, 1


SHORT_INSTR = [0x20000053, 0x20001053, 0x20002053, 0x28000053, 0x28001053,
               0xa0002053, 0xa0001053, 0xa0000053, 0xe0001053]
CONVERT_INSTR = [0xc0000053, 0xc0100053, 0xd0000053, 0xd0100053,
                 0xe0000053, 0xf0000053]


def rounded_integer(value, rm):
    sign = value < 0
    n, d = abs(value).as_integer_ratio()
    q, r = divmod(n, d)
    inc = ((rm == 0 and (2*r > d or (2*r == d and q & 1)))
           or (rm == 4 and 2*r >= d) or (rm == 2 and sign and r)
           or (rm == 3 and not sign and r))
    q += int(bool(inc))
    return -q if sign else q, bool(r)


def round_float(value, rm):
    # Construct a representable FP32 integer factor and an exact residual via FMA
    # only for the zero/small path; general integer conversion uses rational scaling.
    if not value:
        return 0, 0
    sign = value < 0
    n = abs(value)
    exponent = n.bit_length() - 1
    quantum = exponent - 23
    significand, inexact = rounded_integer(Fraction(value << max(-quantum, 0), 1 << max(quantum, 0)), rm)
    significand = abs(significand)
    if significand == 1 << 24:
        significand >>= 1
        exponent += 1
    return (int(sign) << 31) | ((exponent+127) << 23) | (significand & 0x7fffff), int(inexact)


def convert(op, a, integer, rm):
    if op >= 4:
        return (a if op == 4 else integer), 0, int(op == 4)
    if op >= 2:
        value = integer - (1 << 32) if op == 2 and integer >> 31 else integer
        result, flags = round_float(value, rm)
        return result, flags, 0
    lo, hi = (0, 0xffffffff) if op == 1 else (-0x80000000, 0x7fffffff)
    if a & 0x7f800000 == 0x7f800000:
        return (hi if nan(a) or not a >> 31 else lo) & 0xffffffff, 16, 1
    value, inexact = rounded_integer(finite(a), rm)
    if value < lo or value > hi:
        return max(lo, min(hi, value)) & 0xffffffff, 16, 1
    return value & 0xffffffff, int(inexact), 1


def generate(path, unit, tier):
    rng = random.Random(0xF0207)
    total = 0
    with path.open('w') as out:
        def emit(instr, a, b, c, integer, rm, result, flags, dest):
            nonlocal total
            out.write(f'{instr:08x} {a:08x} {b:08x} {c:08x} {integer:08x} '
                      f'{rm:x} {result:08x} {flags:02x} {dest:x}\n')
            total += 1
        # Isolated prefix measures every operation before the streaming stress.
        if unit == 'fma32':
            for op in range(7):
                a,b,c,rm = 0x3f800001,0x3f7ffffe,0xbf800000,0
                emit(arithmetic_instr(op),a,b,c,0,rm,*arithmetic(op,a,b,c,rm),0)
        elif unit == 'short':
            for op in range(9):
                emit(SHORT_INSTR[op],0x3f800000,0xbf800000,0,0,0,
                     *short(op,0x3f800000,0xbf800000))
        else:
            for op in range(6):
                emit(CONVERT_INSTR[op],0x3fc00000,0,0,0x01000001,0,
                     *convert(op,0x3fc00000,0x01000001,0))
        if unit == 'fma32':
            for a, b, c in directed():
                for op, rm in itertools.product(range(4), range(5)):
                    emit(arithmetic_instr(op), a, b, c, 0, rm, *arithmetic(op,a,b,c,rm), 0)
            for a, b, op, rm in itertools.product(VALUES, VALUES, range(4,7), range(5)):
                emit(arithmetic_instr(op),a,b,0,0,rm,*arithmetic(op,a,b,0,rm),0)
            for a,b,c,op,rm in random_cases(10000 if tier == 'smoke' else 1000000):
                emit(arithmetic_instr(op),a,b,c,0,rm,*arithmetic(op,a,b,c,rm),0)
            for _ in range(1000 if tier == 'smoke' else 200000):
                a,b,c = (rng.getrandbits(32) for _ in range(3))
                op,rm = rng.randrange(7),rng.randrange(5)
                emit(arithmetic_instr(op),a,b,c,0,rm,*arithmetic(op,a,b,c,rm),0)
        elif unit == 'short':
            for a,b,op in itertools.product(VALUES,VALUES,range(9)):
                emit(SHORT_INSTR[op],a,b,0,0,0,*short(op,a,b))
            for _ in range(10000 if tier == 'smoke' else 1000000):
                a,b = rng.getrandbits(32),rng.getrandbits(32)
                op = rng.randrange(9)
                emit(SHORT_INSTR[op],a,b,0,0,0,*short(op,a,b))
        else:
            integers = [0,1,2,0x7fffffff,0x80000000,0xffffffff,0x01000001,0x01000003]
            floats = VALUES + [0x4effffff,0x4f000000,0xcf000000,0xcf000001,
                               0x4f7fffff,0x4f800000,0xbf000000,0x3f000000,
                               0x3fc00000,0xbfc00000,0x4b800001]
            for a,integer,op,rm in itertools.product(floats,integers,range(6),range(5)):
                emit(CONVERT_INSTR[op],a,0,0,integer,rm,*convert(op,a,integer,rm))
            for _ in range(10000 if tier == 'smoke' else 1000000):
                a,integer = rng.getrandbits(32),rng.getrandbits(32)
                op,rm = rng.randrange(6),rng.randrange(5)
                emit(CONVERT_INSTR[op],a,0,0,integer,rm,*convert(op,a,integer,rm))
    print(f'Generated {unit}: {total} exact vectors',flush=True)
