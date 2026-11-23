"""planes.py — gpu-spec v0.3 proposal, 2.5/2.6/2.12 pixel arithmetic.
Integer plane stepping and normalized sign/magnitude products; host, no clock domain.
Study-only subclasses compare widths without changing the GPU/Scene API.
"""
from functools import lru_cache

from .arithmetic import divide, logarithm, reciprocal, saturate, shift


@lru_cache(maxsize=None)
def pixel_seed(index, bits):
    midpoint = (1 << 11) + 2 * index + 1
    return divide(1 << (bits - 1 + 11), midpoint)


class PixelArithmetic:
    PLANE_BITS = 32
    MANTISSA_BITS = 18

    def normal(self, value, exponent=0):
        """Signed magnitude with P significant bits; zero has exponent zero."""
        if value == 0:
            return 0, 0
        amount = abs(value).bit_length() - self.MANTISSA_BITS
        mantissa = shift(value, amount)
        if abs(mantissa) == 1 << self.MANTISSA_BITS:
            mantissa = shift(mantissa, 1)
            amount += 1
        return mantissa, exponent + amount

    def multiply(self, a, b):
        return self.normal(a[0] * b[0], a[1] + b[1])

    def subtract(self, a, b):
        # Three alignment guard bits; signed shifts round, including lost operands.
        if b[0] == 0:
            return a
        if a[0] == 0:
            return -b[0], b[1]
        exponent = max(a[1], b[1]) - 3
        value = shift(a[0], exponent - a[1]) - shift(b[0], exponent - b[1])
        return self.normal(value, exponent)

    def inverse(self, value):
        mantissa, exponent = value
        fraction = self.MANTISSA_BITS - 1
        index = (mantissa - (1 << fraction)) >> (fraction - 10)
        seed = pixel_seed(index, self.MANTISSA_BITS)
        product = shift(mantissa * seed, fraction)
        result = shift(seed * ((2 << fraction) - product), fraction)
        return self.normal(result, -2 * fraction - exponent)

    def __init__(self, vertices, area):
        self.origin = (min(v[0] for v in vertices) // 16,
                       min(v[1] for v in vertices) // 16)
        a, b, c = vertices
        edges = ((b, c), (c, a), (a, b))
        dx = [(start[1] - end[1]) * 16 for start, end in edges]
        dy = [(end[0] - start[0]) * 16 for start, end in edges]
        # One area reciprocal, normalized before Q30 so large areas never underflow.
        area_exponent = area.bit_length() - 1
        inverse_area = reciprocal(area, area_exponent)
        self.coefficients = []
        self.exponents = []
        for channel in range(2, 9):
            raw = [vertex[channel] for vertex in vertices]
            # Depth and color have fixed output shifts, avoiding four extra lane shifters.
            bits = (max(raw).bit_length() if channel in (3, 4, 5)
                    else 16 if channel == 2 else 24)
            exponent = bits - self.PLANE_BITS
            values = [shift(value, exponent) for value in raw]
            gradients = [shift(sum(w * v for w, v in zip(weights, values))
                               * inverse_area, 30 + area_exponent) for weights in (dx, dy)]
            start = values[0] + shift(
                (16 * self.origin[0] + 8 - a[0]) * gradients[0]
                + (16 * self.origin[1] + 8 - a[1]) * gradients[1], 4)
            self.coefficients.append((start, *gradients))
            # Input attributes are depth U16, q Q30, uq/vq Q38, colors Q16.
            self.exponents.append(exponent - (0, 30, 38, 38, 16, 16, 16)[channel - 2])
        self.gradients = [[self.normal(self.coefficients[c][axis], self.exponents[c])
                           for c in (1, 2, 3)] for axis in (1, 2)]

    def at(self, x, y):
        """Exact integer expression: stepping must retain these same accumulator bits."""
        dx, dy = x - self.origin[0], y - self.origin[1]
        return [start + dx * gx + dy * gy for start, gx, gy in self.coefficients]

    def shade(self, attrs):
        depth = saturate(shift(attrs[0], -self.exponents[0]), 0, 65535)
        q, uq, vq = [self.normal(attrs[c], self.exponents[c]) for c in (1, 2, 3)]
        w = self.inverse(q)
        uv = [self.multiply(value, w) for value in (uq, vq)]
        coordinates = [shift(value, -exponent - 8) for value, exponent in uv]
        span = 0
        for dq, duq, dvq in self.gradients:
            for gradient, coordinate in zip((duq, dvq), uv):
                delta = self.subtract(gradient, self.multiply(coordinate, dq))
                value, exponent = self.multiply(delta, w)
                span = max(span, shift(abs(value), -exponent - 16))
        lod = logarithm(span) if span else 0
        colors = [saturate(shift(attrs[c], -self.exponents[c]), 0, 255)
                  for c in (4, 5, 6)]
        return depth, *coordinates, lod, colors
