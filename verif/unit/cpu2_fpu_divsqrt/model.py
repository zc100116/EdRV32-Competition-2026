#!/usr/bin/env python3
"""RISC-V DIV/SQRT via exact Fraction arithmetic and integer square root."""
from fractions import Fraction
from math import isqrt


def compute(a, b, square_root, rm, width):
    p, eb = (24, 8) if width == 32 else (53, 11)
    f = p - 1
    bias = (1 << (eb - 1)) - 1
    emask = (1 << eb) - 1
    fracmask = (1 << f) - 1
    infinity = emask << f
    canonical = infinity | (1 << (f - 1))

    def classify(x):
        e = (x >> f) & emask
        m = x & fracmask
        return e == emask and bool(m), e == emask and not m, not (x & ((1 << (width-1))-1))

    an, ai, az = classify(a)
    bn, bi, bz = classify(b)
    sign = (a >> (width-1)) if square_root else ((a ^ b) >> (width-1))
    invalid = ((an and not a & (1 << (f-1)))
               or (not square_root and bn and not b & (1 << (f-1)))
               or (square_root and bool(sign) and not az and not an)
               or (not square_root and ((az and bz) or (ai and bi))))
    if an or (bn and not square_root) or invalid:
        return canonical, 16 if invalid else 0
    if square_root and (az or ai):
        return a, 0
    if not square_root:
        if ai or bz:
            return (sign << (width-1)) | infinity, 8 if bz and not ai else 0
        if az or bi:
            return sign << (width-1), 0

    def finite(x):
        e = (x >> f) & emask
        m = (x & fracmask) | ((1 << f) if e else 0)
        power = (e-bias if e else 1-bias)-f
        return Fraction(m << max(power, 0), 1 << max(-power, 0))

    x = finite(a) if square_root else finite(a) / finite(b)
    n, d = x.numerator, x.denominator
    exponent = n.bit_length() - d.bit_length()
    exponent -= int(n < d << exponent) if exponent >= 0 else int(n << -exponent < d)
    if square_root:
        exponent //= 2
    quantum = max(exponent-f, 1-bias-f)
    scale = 2 if square_root else 1
    n <<= max(-quantum*scale, 0)
    d <<= max(quantum*scale, 0)
    if square_root:
        significand = isqrt(n // d)
        exact = significand * significand * d == n
        midpoint = 4*n - d*(2*significand+1)**2
    else:
        significand, rem = divmod(n, d)
        exact = rem == 0
        midpoint = 2*rem-d
    increment = ((rm == 0 and (midpoint > 0 or (midpoint == 0 and significand & 1)))
                 or (rm == 4 and midpoint >= 0)
                 or (rm == 2 and sign and not exact)
                 or (rm == 3 and not sign and not exact))
    significand += int(increment)
    if significand >= 1 << p:
        significand >>= 1
        exponent += 1
    if exponent > bias:
        to_inf = rm in (0, 4) or (rm == 2 and sign) or (rm == 3 and not sign)
        return (sign << (width-1)) | (infinity if to_inf else infinity-1), 5
    result = significand if exponent < 1-bias else ((exponent+bias) << f) | (significand & fracmask)
    tiny = result < 1 << f
    return (sign << (width-1)) | result, int(not exact) | (2 if tiny and not exact else 0)
