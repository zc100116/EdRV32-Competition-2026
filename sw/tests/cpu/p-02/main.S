/* File: p-02/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 同组 WAW 槽 1 生效，并检查 x0。
 * Clock: clk_sys. */
#include "test.h"
    START
    .balign 8
waw_pair:
    li a0, 17
    li a0, 29
    CHECK a0, 29
    addi zero, a0, 1
    CHECK zero, 0
    .balign 8
waw_second:
    addi a1, zero, -1
    addi a1, zero, 42
    CHECK a1, 42
    la a4, scratch
    li t0, 61
    sw t0, 0(a4)
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
waw_swap:
    addi a0, zero, 17
    lw a0, 0(a4)
    CHECK a0, 61
    FINISH
