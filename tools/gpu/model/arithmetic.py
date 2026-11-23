"""arithmetic.py — gpu-spec 2.4–2.7, G-N1–G-N3 arithmetic proposals.
Host integer arithmetic, independent of any RTL; no clock domain.
"""
from dataclasses import dataclass
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


@dataclass(frozen=True)
class Numeric:
    """Research-only parameters; delete alternatives after specification convergence."""
    matrix_frac: int = 16
    clip_bits: int = 40
    clip_frac: int = 16
    near_numerator: int = 1
    near_denominator: int = 16
    guard: int = 4
    reciprocal_table_bits: int = 10
    reciprocal_iterations: int = 1
    reciprocal_frac: int = 30
    log_table_bits: int = 8
    log_frac: int = 8

    def coefficient(self, value):
        bound = 1 << (15 + self.matrix_frac)
        return saturate(shift(value, 16 - self.matrix_frac), -bound, bound - 1)

    @property
    def near(self):
        return divide(self.near_numerator << self.clip_frac, self.near_denominator)

    def reciprocal(self, value, input_frac):
        """Normalize, midpoint ROM seed Q30, Newton r <- r(2-mr), denormalize."""
        exponent = value.bit_length() - 1
        mantissa = (value >> (exponent - 30) if exponent >= 30
                    else value << (30 - exponent))
        index = (mantissa - (1 << 30)) >> (30 - self.reciprocal_table_bits)
        midpoint = ((1 << 30) + (index << (30 - self.reciprocal_table_bits))
                    + (1 << (29 - self.reciprocal_table_bits)))
        result = reciprocal_seed(midpoint)
        for _ in range(self.reciprocal_iterations):
            product = shift(mantissa * result, 30)
            result = shift(result * ((2 << 30) - product), 30)
        return shift(result, exponent - input_frac + 30 - self.reciprocal_frac)

    def logarithm(self, value, input_frac):
        """Leading-one exponent plus floor-indexed log2(1+i/2^L) ROM, Qlog_frac."""
        exponent = value.bit_length() - 1
        bits = self.log_table_bits
        mantissa = (value >> (exponent - bits) if exponent >= bits
                    else value << (bits - exponent))
        index = mantissa - (1 << bits)
        fraction = logarithm_entry(index, bits, self.log_frac)
        return ((exponent - input_frac) << self.log_frac) + fraction


@lru_cache(maxsize=None)
def reciprocal_seed(midpoint):
    return divide(1 << 60, midpoint)


@lru_cache(maxsize=None)
def logarithm_entry(index, table_bits, output_bits):
    # Construct the ROM without host floating point. 64 fractional bits retain
    # ample guard precision for all research configurations (output <= 8 bits).
    value = (1 << 64) + (index << (64 - table_bits))
    fraction = 0
    precision = output_bits + 16
    for _ in range(precision):
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
