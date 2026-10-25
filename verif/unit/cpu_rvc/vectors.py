"""RV32C encoding table oracle; emit all halfword cases into build/."""
from pathlib import Path

def bits(v, lo, n=1):
    return (v >> lo) & ((1 << n) - 1)

def sext(v, n):
    return v - (1 << n) if v & (1 << (n - 1)) else v

def itype(op, rd, rs, imm, f=0):
    return ((imm & 4095) << 20) | (rs << 15) | (f << 12) | (rd << 7) | op

def rtype(rd, a, b, f=0, ext=0):
    return (ext << 25) | (b << 20) | (a << 15) | (f << 12) | (rd << 7) | 0x33

def store(a, b, imm):
    return ((imm >> 5) << 25) | (b << 20) | (a << 15) | 0x2000 | ((imm & 31) << 7) | 0x23

def jump(rd, imm):
    imm &= (1 << 21) - 1
    return (bits(imm, 20) << 31) | (bits(imm, 1, 10) << 21) | (bits(imm, 11) << 20) | (bits(imm, 12, 8) << 12) | (rd << 7) | 0x6f

def branch(a, imm, ne):
    imm &= 8191
    return (bits(imm, 12) << 31) | (bits(imm, 5, 6) << 25) | (a << 15) | (ne << 12) | (bits(imm, 1, 4) << 8) | (bits(imm, 11) << 7) | 0x63

def expand(c):
    q, f = c & 3, c >> 13
    d, b = bits(c, 7, 5), bits(c, 2, 5)
    a8, b8 = 8 + bits(c, 7, 3), 8 + bits(c, 2, 3)
    sign = bits(c, 12)
    imm = sext((sign << 5) | b, 6)
    if q == 0:
        if f == 0:
            n = (bits(c, 7, 4) << 6) | (bits(c, 11, 2) << 4) | (bits(c, 5) << 3) | (bits(c, 6) << 2)
            return itype(0x13, b8, 2, n) if n else None
        n = (bits(c, 5) << 6) | (bits(c, 10, 3) << 3) | (bits(c, 6) << 2)
        if f == 2:
            return itype(3, b8, a8, n, 2)
        if f == 6:
            return store(a8, b8, n)
    elif q == 1:
        if f == 0:
            return itype(0x13, d, d, imm)
        if f == 2:
            return itype(0x13, d, 0, imm)
        if f in (1, 5):
            n = (sign << 11) | (bits(c, 8) << 10) | (bits(c, 9, 2) << 8) | (bits(c, 6) << 7) | (bits(c, 7) << 6) | (bits(c, 2) << 5) | (bits(c, 11) << 4) | (bits(c, 3, 3) << 1)
            return jump(1 if f == 1 else 0, sext(n, 12))
        if f == 3:
            if d == 2:
                n = (sign << 9) | (bits(c, 3, 2) << 7) | (bits(c, 5) << 6) | (bits(c, 2) << 5) | (bits(c, 6) << 4)
                return itype(0x13, 2, 2, sext(n, 10)) if n else None
            return ((imm & 0xfffff) << 12) | (d << 7) | 0x37 if imm else None
        if f == 4:
            sub = bits(c, 10, 2)
            if sub == 2:
                return itype(0x13, a8, a8, imm, 7)
            if sign:
                return None
            if sub < 2:
                return itype(0x13, a8, a8, b + sub * 1024, 5)
            sel = bits(c, 5, 2)
            return rtype(a8, a8, b8, (0, 4, 6, 7)[sel], 32 if sel == 0 else 0)
        if f in (6, 7):
            n = (sign << 8) | (bits(c, 5, 2) << 6) | (bits(c, 2) << 5) | (bits(c, 10, 2) << 3) | (bits(c, 3, 2) << 1)
            return branch(a8, sext(n, 9), f == 7)
    elif q == 2:
        if f == 0:
            return None if sign else itype(0x13, d, d, b, 1)
        if f == 2 and d:
            n = (bits(c, 2, 2) << 6) | (sign << 5) | (bits(c, 4, 3) << 2)
            return itype(3, d, 2, n, 2)
        if f == 4:
            if b:
                return rtype(d, d if sign else 0, b)
            if sign and not d:
                return 0x00100073
            return itype(0x67, sign, d, 0) if d else None
        if f == 6:
            n = (bits(c, 7, 2) << 6) | (bits(c, 9, 4) << 2)
            return store(2, b, n)
    return None

Path('build/unit').mkdir(parents=True, exist_ok=True)
with Path('build/unit/cpu_rvc_vectors.hex').open('w') as out:
    for encoding in range(65536):
        result = expand(encoding)
        out.write(f'{(1 << 32) if result is None else result:09x}\n')
