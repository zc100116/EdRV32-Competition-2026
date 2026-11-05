/* File: l-02/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan L-02.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a0, 7
    sw a0, 0(a4)
    fence
    li a2, 1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
slot0_load:
    lw a3, 0(a1)
    addi a7, zero, 1
slot0_branch:
    bne a3, a0, fail
slot0_younger:
    addi a6, zero, 9
    li a2, 1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
early_load:
    lw a3, 0(a4)
early_branch:
    bne a3, a0, fail
    li a2, 1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
multiply_load:
    mul a3, a0, a2
multiply_branch:
    bne a3, a0, fail
    FINISH
