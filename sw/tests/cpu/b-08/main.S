/* File: b-08/main.S; Spec: cpu-spec 4.2-4.5; cpu-testplan B-08.
 * Description: Check ordered slots across pipeline assignment.
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
jal_older:
    addi a0, zero, 17
jal_slot1:
    jal a1, target
    addi a0, a0, 100
target:
    CHECK a0, 17
    la t0, jal_slot1
    addi t0, t0, 4
    bne a1, t0, fail
    FINISH
