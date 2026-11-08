/* File: b-09/main.S; Spec: cpu-spec 4.2-4.5; cpu-testplan B-09.
 * Description: Check ordered slots across pipeline assignment.
 * Clock: clk_sys. */
#include "test.h"
    START
    li t0, 8
    csrw mcountinhibit, t0
    li t0, 7
    csrw mhpmevent3, t0
    csrw mhpmcounter3, zero
    csrw mcountinhibit, zero
    li a0, 1
    la a2, done
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
bb0:
    beq a0, zero, fail
bb1:
    beq a0, zero, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
bj0:
    beq a0, zero, fail
bj1:
    jal a1, jj0
    .balign 8
jj0:
    jal a1, jj1
jj1:
    jalr zero, 0(a2)
done:
    li t0, 8
    csrw mcountinhibit, t0
    csrr t0, mhpmcounter3
#ifndef SPIKE_SMOKE
    CHECK t0, 2
#endif
    CHECK a0, 1
    FINISH
