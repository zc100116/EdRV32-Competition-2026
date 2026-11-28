// File: reference.c
// Spec: fpu-spec 2.1-2.3; fpu-testplan 4 FT01.
// Description: RISC-V bit semantics around Release3e RISCV SoftFloat.
// Clock: host only; global SoftFloat state makes calls sequential.
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "softfloat.h"

// Operation IDs are shared with reference.py, independent of DUT RTL.
enum {
    ADD, SUB, MUL, DIV, SQRT, MADD, MSUB, NMADD, NMSUB,
    MIN, MAX, EQ, LT, LE, CLASS, SGNJ, SGNJN, SGNJX,
    TO_W, TO_WU, FROM_W, FROM_WU, TO_S, TO_D, MV_X_W, MV_W_X,
    LOAD, STORE
};

static bool is_nan(uint64_t x, unsigned width)
{
    uint64_t exp = width == 32 ? 0x7f800000 : UINT64_C(0x7ff0000000000000);
    uint64_t frac = width == 32 ? 0x007fffff : UINT64_C(0x000fffffffffffff);
    return (x & exp) == exp && (x & frac) != 0;
}

static bool is_snan(uint64_t x, unsigned width)
{
    uint64_t quiet = width == 32 ? 0x00400000 : UINT64_C(0x0008000000000000);
    return is_nan(x, width) && !(x & quiet);
}

static uint32_t classify(uint64_t x, unsigned width)
{
    unsigned shift = width == 32 ? 23 : 52;
    uint64_t emask = width == 32 ? 255 : 2047;
    uint64_t frac = x & ((UINT64_C(1) << shift) - 1);
    uint64_t exp = (x >> shift) & emask;
    bool sign = (x >> (width - 1)) != 0;
    unsigned index;
    if (exp == emask) {
        index = frac ? (is_snan(x, width) ? 8 : 9) : (sign ? 0 : 7);
    } else if (exp == 0) {
        index = frac ? (sign ? 2 : 5) : (sign ? 3 : 4);
    } else {
        index = sign ? 1 : 6;
    }
    return 1u << index;
}

uint64_t fpu_ref(unsigned op, unsigned width, unsigned flen, uint64_t a,
                 uint64_t b, uint64_t c, uint32_t integer, unsigned rm,
                 uint32_t *flags, uint32_t *int_dest)
{
    static const uint8_t rounding[] = {0, 1, 2, 3, 4};
    uint64_t canonical = width == 32 ? 0x7fc00000 : UINT64_C(0x7ff8000000000000);
    uint64_t mask = width == 32 ? UINT32_MAX : UINT64_MAX;
    uint64_t sign = UINT64_C(1) << (width - 1);
    uint64_t result = 0;
    unsigned result_width = width;
    softfloat_roundingMode = rounding[rm];
    softfloat_detectTininess = softfloat_tininess_afterRounding;
    softfloat_exceptionFlags = 0;
    *int_dest = 0;
    // Raw moves/stores do not inspect NaN boxing (fpu-spec 2.3).
    if (op == MV_X_W || op == STORE) {
        *int_dest = op == MV_X_W;
        *flags = 0;
        return a & mask;
    }
    if (op == MV_W_X || op == LOAD) {
        result = op == MV_W_X ? integer : a;
        goto finish;
    }
    if (width == 32 && flen == 64) {
        if ((a >> 32) != UINT32_MAX) a = canonical;
        if ((b >> 32) != UINT32_MAX) b = canonical;
        if ((c >> 32) != UINT32_MAX) c = canonical;
    }
    a &= mask;
    b &= mask;
    c &= mask;
    float32_t a32 = {(uint32_t)a};
    float32_t b32 = {(uint32_t)b};
    float32_t c32 = {(uint32_t)c};
    float64_t a64 = {a};
    float64_t b64 = {b};
    float64_t c64 = {c};
    if (op >= MADD && op <= NMSUB) {
        // Negate multiplicand/addend before fused rounding, including signed zero.
        if (op == NMADD || op == NMSUB) a ^= sign;
        if (op == MSUB || op == NMADD) c ^= sign;
        a32.v = (uint32_t)a;
        c32.v = (uint32_t)c;
        a64.v = a;
        c64.v = c;
    }
    switch (op) {
    case ADD: result = width == 32 ? f32_add(a32, b32).v : f64_add(a64, b64).v; break;
    case SUB: result = width == 32 ? f32_sub(a32, b32).v : f64_sub(a64, b64).v; break;
    case MUL: result = width == 32 ? f32_mul(a32, b32).v : f64_mul(a64, b64).v; break;
    case DIV: result = width == 32 ? f32_div(a32, b32).v : f64_div(a64, b64).v; break;
    case SQRT: result = width == 32 ? f32_sqrt(a32).v : f64_sqrt(a64).v; break;
    case MADD: case MSUB: case NMADD: case NMSUB:
        result = width == 32 ? f32_mulAdd(a32, b32, c32).v : f64_mulAdd(a64, b64, c64).v;
        break;
    case MIN: case MAX: {
        if (is_snan(a, width) || is_snan(b, width)) softfloat_exceptionFlags = 16;
        if (is_nan(a, width)) result = is_nan(b, width) ? canonical : b;
        else if (is_nan(b, width)) result = a;
        else if (((a | b) & ~sign) == 0) result = op == MIN ? a | b : a & b;
        else {
            bool less = width == 32 ? f32_lt(a32, b32) : f64_lt(a64, b64);
            result = (less == (op == MIN)) ? a : b;
        }
        break;
    }
    case EQ:
        *int_dest = 1;
        result = width == 32 ? f32_eq(a32, b32) : f64_eq(a64, b64);
        break;
    case LT:
        *int_dest = 1;
        result = width == 32 ? f32_lt(a32, b32) : f64_lt(a64, b64);
        break;
    case LE:
        *int_dest = 1;
        result = width == 32 ? f32_le(a32, b32) : f64_le(a64, b64);
        break;
    case CLASS: *int_dest = 1; result = classify(a, width); break;
    case SGNJ: result = (a & ~sign) | (b & sign); break;
    case SGNJN: result = (a & ~sign) | ((~b) & sign); break;
    case SGNJX: result = a ^ (b & sign); break;
    case TO_W:
        *int_dest = 1;
        result = (uint32_t)(width == 32 ? f32_to_i32(a32, rounding[rm], true)
                                     : f64_to_i32(a64, rounding[rm], true));
        break;
    case TO_WU:
        *int_dest = 1;
        result = (uint32_t)(width == 32 ? f32_to_ui32(a32, rounding[rm], true)
                                     : f64_to_ui32(a64, rounding[rm], true));
        break;
    case FROM_W:
        result = width == 32 ? i32_to_f32((int32_t)integer).v
                            : i32_to_f64((int32_t)integer).v;
        break;
    case FROM_WU: result = width == 32 ? ui32_to_f32(integer).v : ui32_to_f64(integer).v;
        break;
    case TO_S: result_width = 32; result = f64_to_f32(a64).v; break;
    case TO_D: result_width = 64; result = f32_to_f64(a32).v; break;
    default: abort();
    }
finish:
    if (*int_dest) result &= UINT32_MAX;
    else if (result_width == 32) {
        result &= UINT32_MAX;
        if (flen == 64) result |= UINT64_C(0xffffffff00000000);
    }
    *flags = softfloat_exceptionFlags;
    return result;
}
