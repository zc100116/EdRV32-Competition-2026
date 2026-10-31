"""Task T-UI1: host production parser/matrix/gamma and VIN 2.8 reference tests."""
import ctypes
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[3]
LIB = ctypes.CDLL(str(ROOT / 'build/sw/demo/parameters.so'))


class Parameters(ctypes.Structure):
    _fields_ = [('geo', ctypes.c_int), ('value', ctypes.c_int * 11)]


LIB.demo_parameters_matrix.restype = ctypes.c_char_p
LIB.affine_inverse.restype = ctypes.c_char_p


class ParameterTest(unittest.TestCase):
    def parse(self, text, expected=0):
        parameters = Parameters()
        result = LIB.demo_parameters_parse(text.encode(), ctypes.byref(parameters))
        self.assertEqual(result, expected)
        return parameters

    def test_pix_parser_and_gamma(self):
        p = self.parse('pix set 1 511 -256 1 2200 6 5 1 1 255 1')
        self.assertEqual(list(p.value), [1, 511, -256, 1, 2200, 6, 5, 1, 1, 255, 1])
        for text in ('pix set 1 512 0 0 1000 0 0 0 0 128 0',
                     'pix set 1 256 -257 0 1000 0 0 0 0 128 0',
                     'pix set 0 256 0 1 0 0 0 0 0 128 0',
                     'pix set 0 256 0 1 1000 7 0 0 0 128 0',
                     'pix set 0 256 0 1 1000 0 0 0 0 128 0 extra',
                     'pix set 0 256 0 1 1000 0 0 0 0 128',
                     'pix set 99999999999999999999999999'):
            self.parse(text, -1)
        self.parse('pix gamma', 1)
        for gamma in (1, 500, 1000, 2200, 2147483647):
            table = (ctypes.c_ubyte * 256)()
            LIB.demo_parameters_gamma(table, gamma)
            expected = [int(255 * (i / 255) ** (1000 / gamma) + .5) for i in range(256)]
            self.assertLessEqual(max(abs(a - b) for a, b in zip(table, expected)), 1)

    def test_gamma_complete_integer_domain(self):
        # Each reference output is monotone in gamma. Its only transitions occur at
        # 255*(i/255)^(1000/gamma) = level-0.5. The integer implementation is also
        # monotone: log/gamma decreases; the exp2 interpolant and rounding preserve
        # order. Checking both integer ends of every constant-output interval thus
        # covers every gamma in 1..INT_MAX, including the saturated tail.
        critical = {1, 2147483647}
        for i in range(1, 255):
            for level in range(1, 256):
                boundary = 1000 * math.log(i / 255) / math.log((level - .5) / 255)
                lower = max(1, int(boundary))
                critical.update((max(1, lower - 1), lower, lower + 1, lower + 2))
        maximum = 0
        table = (ctypes.c_ubyte * 256)()
        for gamma in sorted(critical):
            LIB.demo_parameters_gamma(table, gamma)
            expected = [int(255 * (i / 255) ** (1000 / gamma) + .5) for i in range(256)]
            error = max(abs(a - b) for a, b in zip(table, expected))
            self.assertLessEqual(error, 1, f'gamma={gamma}')
            maximum = max(maximum, error)
        print(f'Gamma 1..INT_MAX: {len(critical)} interval-boundary tables; max error={maximum}')

    def test_geo_matrix_and_errors(self):
        matrix = (ctypes.c_int32 * 6)()
        maximum = 0
        cases = ((500, 500, 17, -9, 1, 0), (1000, 2000, -1280, 720, 0, 1),
                 (700, 1300, 17, -9, 1, 1), (2147483647, 1000, 17, -9, 0, 0),
                 (1000000000, 1000000000, 2147483647, -2147483647, 1, 0))
        for angle in range(3600):
            for sx, sy, tx, ty, mx, my in cases:
                p = self.parse(f'geo set 1 {angle} {sx} {sy} {tx} {ty} {mx} {my}')
                self.assertIsNone(LIB.demo_parameters_matrix(ctypes.byref(p), matrix))
                radians = math.radians(angle / 10)
                x, y = (-1 if mx else 1) * 1000 / sx, (-1 if my else 1) * 1000 / sy
                a, b = x * math.cos(radians), x * math.sin(radians)
                c, d = -y * math.sin(radians), y * math.cos(radians)
                expected = [a, b, 639.5 - a * (639.5 + tx) - b * (359.5 + ty),
                            c, d, 359.5 - c * (639.5 + tx) - d * (359.5 + ty)]
                for actual, value in zip(matrix, expected):
                    error = abs(actual - round(value * 65536))
                    self.assertLessEqual(error, 1, (angle, sx, sy, tx, ty, list(matrix)))
                    maximum = max(maximum, error)
        # Near-cancelling large translations amplify premature trig rounding.
        for angle, tx, ty in ((450, 2147483647, -2147483647),
                              (1350, 2147483647, 2147483647)):
            p = self.parse(f'geo set 1 {angle} 500 2147483647 {tx} {ty} 0 0')
            self.assertIsNone(LIB.demo_parameters_matrix(ctypes.byref(p), matrix))
            r = math.radians(angle / 10)
            a, b = 2 * math.cos(r), 2 * math.sin(r)
            c = -1000 * math.sin(r) / 2147483647
            d = 1000 * math.cos(r) / 2147483647
            values = [a, b, 639.5 - a * (639.5 + tx) - b * (359.5 + ty),
                      c, d, 359.5 - c * (639.5 + tx) - d * (359.5 + ty)]
            for actual, value in zip(matrix, values):
                error = abs(actual - round(value * 65536))
                self.assertLessEqual(error, 1)
                maximum = max(maximum, error)
        print(f'GEO 3600 angles x {len(cases)} transforms plus cancellation: '
              f'max error={maximum} LSB')
        for text in ('geo set 1 450 100 100 0 0 0 0',
                     'geo set 1 0 200 200 0 0 0 0'):
            p = self.parse(text)
            self.assertIn(b'geo-spec 2.4', LIB.demo_parameters_matrix(ctypes.byref(p), matrix))
        p = self.parse('geo set 1 0 1000 1000 1000000 0 0 0')
        self.assertIn(b'Q16.16', LIB.demo_parameters_matrix(ctypes.byref(p), matrix))
        for text in ('geo set 1 0 0 1000 0 0 0 0', 'geo set 1 0 1000 -1 0 0 0 0',
                     'geo set 2 0 1000 1000 0 0 0 0', 'geo set 1 0 1000 1000 0 0 2 0'):
            self.parse(text, -1)
        p = self.parse('geo set 0 0 1000 1000 0 0 0 0')
        self.assertIsNone(LIB.demo_parameters_matrix(ctypes.byref(p), matrix))
        self.assertEqual(list(matrix), [65536, 0, 0, 0, 65536, 0])

    def test_cpu_ch2_byte_exact_vin_reference(self):
        # Random full frame covers every RGB565 value and mixed 2x2 rounding cases.
        source = random.Random(20261031).randbytes(1280 * 720 * 2)
        output = (ctypes.c_ubyte * 983040)()
        LIB.demo_ch2(source, output)
        expected = bytearray(bytes([57, 57, 57, 0]) * (640 * 384))
        for y in range(360):
            for x in range(640):
                samples = []
                for dy, dx in ((0, 0), (0, 1), (1, 0), (1, 1)):
                    offset = ((y * 2 + dy) * 1280 + x * 2 + dx) * 2
                    pixel = int.from_bytes(source[offset:offset + 2], 'little')
                    r, g, b = pixel >> 11, (pixel >> 5) & 63, pixel & 31
                    samples.append(((r << 3) | (r >> 2), (g << 2) | (g >> 4),
                                    (b << 3) | (b >> 2)))
                for channel in range(3):
                    average = (sum(pixel[channel] for pixel in samples) + 2) // 4
                    expected[((y + 12) * 640 + x) * 4 + channel] = round(average * 127 / 255)
        self.assertEqual(bytes(output), expected)


if __name__ == '__main__':
    unittest.main()
