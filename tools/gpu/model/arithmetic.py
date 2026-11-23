"""arithmetic.py — gpu-spec v0.2 2.4–2.12 fixed integer arithmetic.
Host integer arithmetic, independent of any RTL; no clock domain.
"""
from functools import lru_cache


def divide(numerator, denominator):
    """Nearest integer, exact ties away from zero, including negative denominators."""
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    sign = -1 if numerator < 0 else 1
    return sign * ((abs(numerator) + denominator // 2) // denominator)


def shift(value, bits):
    return divide(value, 1 << bits) if bits > 0 else value << -bits


def saturate(value, low, high):
    return min(high, max(low, value))


def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def d(value):
    temp = value + 128
    return (temp + (temp >> 8)) >> 8


def expand(value):
    r, g, b = value >> 11, (value >> 5) & 63, value & 31
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def p565(rgb):
    r, g, b = rgb
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


# gpu-spec v0.2 2.4–2.6: fixed formats and clipping planes.
CLIP_FRAC = 16
CLIP_BITS = 40
W_NEAR = 1 << 12
GUARD = 4
RECIPROCAL_FRAC = 30
LOG_FRAC = 8


def reciprocal(value, input_frac):
    """Q30 midpoint ROM (10-bit index), one Newton iteration, Q30 output (2.12)."""
    exponent = value.bit_length() - 1
    mantissa = (value >> (exponent - 30) if exponent >= 30
                else value << (30 - exponent))
    index = (mantissa - (1 << 30)) >> 20
    midpoint = (1 << 30) + (index << 20) + (1 << 19)
    seed = reciprocal_seed(midpoint)
    product = shift(mantissa * seed, 30)
    result = shift(seed * ((2 << 30) - product), 30)
    return shift(result, exponent - input_frac)


def logarithm(value):
    """Leading-one exponent plus 8-bit-index ROM; Q16 span to Q8 LOD (2.6)."""
    exponent = value.bit_length() - 1
    mantissa = value >> (exponent - 8) if exponent >= 8 else value << (8 - exponent)
    fraction = logarithm_entry(mantissa - 256)
    return ((exponent - 16) << 8) + fraction


@lru_cache(maxsize=None)
def reciprocal_seed(midpoint):
    return divide(1 << 60, midpoint)


@lru_cache(maxsize=None)
def logarithm_entry(index):
    # Construct the ROM without host floating point. 64 fractional bits retain
    # ample guard precision for the specified Q8 output.
    value = (1 << 64) + (index << 56)
    fraction = 0
    for _ in range(24):
        value = (value * value) >> 64
        bit = value >= (2 << 64)
        if bit:
            value >>= 1
        fraction = (fraction << 1) | bit
    return shift(fraction, 16)



def edge(a, b, x, y):
    return (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])


def top_left(a, b):
    # Positive-area triangles in y-down coordinates: upward edges and rightward tops.
    return b[1] < a[1] or (b[1] == a[1] and b[0] > a[0])
