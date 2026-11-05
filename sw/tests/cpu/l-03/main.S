/* File: l-03/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan L-03.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a0, 7
    sw a0, 0(a4)
    fence
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
young_fault_load:
    lw a3, 0(a1)
young_fault_branch:
    beq a3, a0, young_fault_resume
young_fault:
    .word 0xffffffff
young_fault_resume:
    CHECK a0, 7
    li t2, 1
    EXPECT 4, t2, oldest_lcb_fault, oldest_lcb_resume
    addi a1, a4, 0
oldest_lcb_fault:
    lw a3, 1(zero)
oldest_lcb_branch:
    beq a3, a0, fail
oldest_lcb_resume:
    CHECK a0, 7
#ifndef SPIKE_SMOKE
    li t0, 0x800
    csrw mie, t0
    csrsi mstatus, 8
    li t2, 0
    EXPECT 0x8000000b, t2, irq_lcb_load, irq_lcb_resume
    addi a1, a4, 0
irq_lcb_load:
    lw a3, 0(a1)
irq_lcb_branch:
    beq a3, a0, fail
irq_lcb_resume:
    csrw mie, zero
    CHECK a0, 7
#endif
    FINISH
