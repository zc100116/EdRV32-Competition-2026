#!/usr/bin/env python3
"""GPU v2 §2.4 integer FP32 RNE reference, independent of RTL.

Finite operations use exact signed integers and binary exponents.  IEEE special
values below are the specification's development initial values (G2-07).
"""
import struct


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def value(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def finite(word):
    exponent = (word >> 23) & 255
    mantissa = (word & 0x7fffff) | (0x800000 if exponent else 0)
    return (-mantissa if word >> 31 else mantissa), (exponent or 1) - 150


def rshift_even(number, shift):
    if shift <= 0:
        return number << -shift
    quotient, remainder = divmod(number, 1 << shift)
    halfway = 1 << (shift - 1)
    return quotient + (remainder > halfway or (remainder == halfway and quotient & 1))


def pack(number, exponent, zero_sign=0):
    if not number:
        return zero_sign << 31
    sign = int(number < 0)
    number = abs(number)
    top = number.bit_length() - 1 + exponent
    if top < -126:
        mantissa = rshift_even(number, -149 - exponent)
        return (sign << 31) | mantissa
    mantissa = rshift_even(number, number.bit_length() - 24)
    if mantissa == 1 << 24:
        mantissa >>= 1
        top += 1
    if top > 127:
        return (sign << 31) | 0x7f800000
    return (sign << 31) | ((top + 127) << 23) | (mantissa & 0x7fffff)


def nan(word):
    return word & 0x7fffffff > 0x7f800000


def inf(word):
    return word & 0x7fffffff == 0x7f800000


def mul(a, b):
    return fma(a, b, ((a ^ b) >> 31) << 31)


def add(a, b):
    return fma(a, 0x3f800000, b)


def fma(a, b, c):
    psign = (a ^ b) >> 31
    if nan(a) or nan(b) or nan(c):
        return 0x7fc00000
    if ((inf(a) and b & 0x7fffffff == 0)
            or (inf(b) and a & 0x7fffffff == 0)):
        return 0x7fc00000
    if inf(a) or inf(b):
        if inf(c) and c >> 31 != psign:
            return 0x7fc00000
        return (psign << 31) | 0x7f800000
    if inf(c):
        return c
    ma, ea = finite(a)
    mb, eb = finite(b)
    mc, ec = finite(c)
    ep = ea + eb
    exponent = min(ep, ec)
    total = (ma * mb << (ep - exponent)) + (mc << (ec - exponent))
    zero_sign = psign if psign == c >> 31 else 0
    return pack(total, exponent, zero_sign)


def dot(a, b, count=4):
    products = [mul(a[i], b[i]) if i < count else 0 for i in range(4)]
    return add(add(products[0], products[1]), add(products[2], products[3]))


if __name__ == '__main__':
    assert dot([0x3f800001, 0x3f800000, 0, 0],
               [0x3f7ffffe, 0xbf800000, 0, 0], 3) == 0
    assert fma(0x3f800001, 0x3f7ffffe, 0xbf800000) == 0xa8800000
    assert mul(1, 0x3f000000) == 0
    assert mul(3, 0x3f000000) == 2
    print('PASS integer FP32 reference: staged cancellation and subnormal RNE')
