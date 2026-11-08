/* File: a-03/main.S; Spec: cpu-spec 4.4, 4.10; cpu-testplan A-03.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a0, 0
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
spec_branch:
    beq zero, zero, spec_resume
spec_branch_load:
    lw a1, 32(a4)
    addi a0, a0, 1
spec_resume:
    CHECK a0, 0
    li t2, 0
    EXPECT 11, t2, spec_fault, spec_trap_resume
spec_fault:
    ecall
spec_trap_load:
    lw a1, 64(a4)
    addi a0, a0, 1
spec_trap_resume:
    CHECK a0, 0
after_branch_probe:
    lw a1, 32(a4)
after_trap_probe:
    lw a2, 64(a4)
    CHECK a1, 0
    CHECK a2, 0
#ifndef SPIKE_SMOKE
    li t0, 0x800
    csrw mie, t0
    csrsi mstatus, 8
    li t2, 0
    EXPECT 0x8000000b, t2, spec_irq, spec_irq_resume
spec_irq:
    addi a7, zero, 1
    nop
spec_irq_load:
    lw a1, 96(a4)
spec_irq_resume:
    csrw mie, zero
after_irq_probe:
    lw a1, 96(a4)
    CHECK a1, 0
#endif
    FINISH
