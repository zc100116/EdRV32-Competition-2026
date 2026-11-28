#!/usr/bin/env python3
"""Exact RISC-V FP64 fused arithmetic; no host floating-point arithmetic."""
from fractions import Fraction


def finite(bits):
    exponent = (bits >> 52) & 2047
    mantissa = (bits & 0xfffffffffffff) | (0x10000000000000 if exponent else 0)
    power = (exponent - 1023 if exponent else -1022) - 52
    value = Fraction(mantissa << max(power, 0), 1 << max(-power, 0))
    return -value if bits >> 63 else value


def fma(a, b, c, op, rm):
    operands = (a, b, c)
    exponents = [(x >> 52) & 2047 for x in operands]
    fractions = [x & 0xfffffffffffff for x in operands]
    nan = [e == 2047 and f != 0 for e, f in zip(exponents, fractions)]
    inf = [e == 2047 and f == 0 for e, f in zip(exponents, fractions)]
    zero = [(x & 0x7fffffffffffffff) == 0 for x in operands]
    ps = ((a ^ b) >> 63) ^ (op >> 1)
    cs = (c >> 63) ^ (op & 1)
    invalid_product = (zero[0] and inf[1]) or (zero[1] and inf[0])
    product_inf = (inf[0] or inf[1]) and not (nan[0] or nan[1])
    invalid_sum = product_inf and inf[2] and ps != cs and not invalid_product
    invalid = (any(n and not (f & 0x8000000000000) for n, f in zip(nan, fractions))
               or invalid_product or invalid_sum)
    if any(nan) or invalid:
        return 0x7ff8000000000000, 16 if invalid else 0
    if product_inf or inf[2]:
        return ((ps if product_inf else cs) << 63) | 0x7ff0000000000000, 0
    product = finite(a) * finite(b)
    addend = finite(c)
    exact = (-product if op & 2 else product) + (-addend if op & 1 else addend)
    if not exact:
        return (ps if ps == cs else int(rm == 2)) << 63, 0
    sign = int(exact < 0)
    exact = abs(exact)
    numerator, denominator = exact.numerator, exact.denominator
    exponent = numerator.bit_length() - denominator.bit_length()
    if exponent >= 0:
        exponent -= int(numerator < (denominator << exponent))
    else:
        exponent -= int((numerator << -exponent) < denominator)
    quantum = max(exponent - 52, -1074)
    scaled_n = numerator << max(-quantum, 0)
    scaled_d = denominator << max(quantum, 0)
    significand, remainder = divmod(scaled_n, scaled_d)
    inexact = remainder != 0
    increment = ((rm == 0 and (2 * remainder > scaled_d
                               or (2 * remainder == scaled_d and significand & 1)))
                 or (rm == 2 and sign and inexact)
                 or (rm == 3 and not sign and inexact)
                 or (rm == 4 and 2 * remainder >= scaled_d))
    significand += int(increment)
    if significand >= 0x20000000000000:
        significand >>= 1
        exponent += 1
    if exponent > 1023:
        infinity = rm in (0, 4) or (rm == 2 and sign) or (rm == 3 and not sign)
        return (sign << 63) | (0x7ff0000000000000 if infinity else 0x7fefffffffffffff), 5
    if exponent < -1022:
        # Rounding can promote the largest subnormal to the minimum normal.
        bits = significand
    else:
        bits = ((exponent + 1023) << 52) | (significand & 0xfffffffffffff)
    tiny = bits < 0x10000000000000
    return (sign << 63) | bits, int(inexact) | (2 if tiny and inexact else 0)
