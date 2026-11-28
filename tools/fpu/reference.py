#!/usr/bin/env python3
# File: reference.py
# Spec: fpu-spec 2.1-2.3; fpu-testplan FT01.
# Description: Python binding and ISA operation table for the independent reference.
# Clock: host only.
import ctypes
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NAMES = ('add sub mul div sqrt madd msub nmadd nmsub min max eq lt le class '
         'sgnj sgnjn sgnjx to_w to_wu from_w from_wu to_s to_d mv_x_w mv_w_x '
         'load store').split()
ROUNDING = ['-rnear_even', '-rminMag', '-rmin', '-rmax', '-rnear_maxMag']
ROUNDED = set(NAMES[:9] + NAMES[18:24])


class Reference:
    def __init__(self):
        self.lib = ctypes.CDLL(str(ROOT / 'build/fpu/reference.so'))
        self.call = self.lib.fpu_ref
        self.call.argtypes = ([ctypes.c_uint] * 3 + [ctypes.c_uint64] * 3
                              + [ctypes.c_uint32, ctypes.c_uint]
                              + [ctypes.POINTER(ctypes.c_uint32)] * 2)
        self.call.restype = ctypes.c_uint64

    def evaluate(self, op, width, flen, a=0, b=0, c=0, integer=0, rm=0):
        flags = ctypes.c_uint32()
        dest = ctypes.c_uint32()
        result = self.call(NAMES.index(op), width, flen, a, b, c, integer, rm,
                           ctypes.byref(flags), ctypes.byref(dest))
        return result, flags.value, dest.value


def box(value, width, flen):
    return value | (0xffffffff00000000 if width == 32 and flen == 64 else 0)


def instruction(op, width, rm):
    """Encode rd=f0/x0, rs1=f1/x1, rs2=f2, rs3=f3; no DUT decoder dependency."""
    fmt = int(width == 64)
    if op in ['madd', 'msub', 'nmsub', 'nmadd']:
        code = dict(madd=0x43, msub=0x47, nmsub=0x4b, nmadd=0x4f)[op]
        return (3 << 27) | (fmt << 25) | (2 << 20) | (1 << 15) | (rm << 12) | code
    if op in ['load', 'store']:
        return ((1 << 15) | ((2 + fmt) << 12)
                | (0x07 if op == 'load' else (1 << 20) | 0x27))
    funcs = dict(add=0, sub=4, mul=8, div=12, sqrt=44, sgnj=16, sgnjn=16,
                 sgnjx=16, min=20, max=20, eq=80, lt=80, le=80, to_w=96,
                 to_wu=96, from_w=104, from_wu=104, to_s=32, to_d=32,
                 **{'class': 112, 'mv_x_w': 112, 'mv_w_x': 120})
    funct3 = dict(sgnj=0, sgnjn=1, sgnjx=2, min=0, max=1, eq=2, lt=1, le=0,
                  **{'class': 1, 'mv_x_w': 0, 'mv_w_x': 0}).get(op, rm)
    rs2 = 2
    if op in ['sqrt', 'class', 'mv_x_w', 'mv_w_x', 'to_w', 'from_w']:
        rs2 = 0
    if op in ['to_wu', 'from_wu', 'to_s']:
        rs2 = 1
    if op == 'to_d':
        rs2 = 0
    dest_fmt = 0 if op == 'to_s' else 1 if op == 'to_d' else fmt
    return ((funcs[op] | dest_fmt) << 25) | (rs2 << 20) | (1 << 15) | (funct3 << 12) | 0x53


def operations(flen):
    for width in ([32] if flen == 32 else [32, 64]):
        for op in NAMES:
            if op == 'to_s' and width != 64 or op == 'to_d' and width != 32:
                continue
            if flen == 32 and op in ['to_s', 'to_d']:
                continue
            if width == 64 and op in ['mv_x_w', 'mv_w_x']:
                continue
            yield op, width


def testfloat_function(op, width):
    fp = f'f{width}'
    if op in ['add', 'sub', 'mul', 'div', 'sqrt', 'eq', 'lt', 'le']:
        return f'{fp}_{op}'
    if op in ['madd', 'msub', 'nmadd', 'nmsub']:
        return f'{fp}_mulAdd'
    if op in ['to_w', 'to_wu']:
        return f'{fp}_to_{"i32" if op == "to_w" else "ui32"}'
    if op in ['from_w', 'from_wu']:
        return f'{"i32" if op == "from_w" else "ui32"}_to_{fp}'
    if op in ['to_s', 'to_d']:
        return f'{fp}_to_f{32 if op == "to_s" else 64}'
    return None
