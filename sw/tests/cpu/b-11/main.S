/* File: b-11/main.S; Spec: cpu-spec 4.4, 4.10; cpu-testplan B-11.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    li t2, 0
    EXPECT 11, t2, priority_trap_0, priority_trap_0_resume
priority_trap_0:
    ecall
priority_trap_0_branch:
    beq zero, zero, priority_trap_0_wrong
    jal zero, priority_trap_0_wrong
priority_trap_0_wrong:
    addi a0, a0, 99
priority_trap_0_resume:
    CHECK a0, 0
    EXPECT 11, t2, priority_trap_1, priority_trap_1_resume
priority_trap_1:
    ecall
    nop
priority_trap_1_branch:
    beq zero, zero, priority_trap_1_wrong
    jal zero, priority_trap_1_wrong
priority_trap_1_wrong:
    addi a0, a0, 99
priority_trap_1_resume:
    CHECK a0, 0
    EXPECT 11, t2, priority_trap_2, priority_trap_2_resume
priority_trap_2:
    ecall
    nop
    nop
priority_trap_2_branch:
    beq zero, zero, priority_trap_2_wrong
    jal zero, priority_trap_2_wrong
priority_trap_2_wrong:
    addi a0, a0, 99
priority_trap_2_resume:
    CHECK a0, 0
    la t0, priority_mret_0_resume
    csrw mepc, t0
priority_mret_0:
    mret
priority_mret_0_branch:
    beq zero, zero, priority_mret_0_wrong
priority_mret_0_wrong:
    addi a0, a0, 99
priority_mret_0_resume:
    CHECK a0, 0
    la t0, priority_mret_1_resume
    csrw mepc, t0
priority_mret_1:
    mret
    nop
priority_mret_1_branch:
    beq zero, zero, priority_mret_1_wrong
priority_mret_1_wrong:
    addi a0, a0, 99
priority_mret_1_resume:
    CHECK a0, 0
    la t0, priority_mret_2_resume
    csrw mepc, t0
priority_mret_2:
    mret
    nop
    nop
priority_mret_2_branch:
    beq zero, zero, priority_mret_2_wrong
priority_mret_2_wrong:
    addi a0, a0, 99
priority_mret_2_resume:
    CHECK a0, 0
priority_fence_0:
    fence.i
priority_fence_0_branch:
    beq zero, zero, priority_fence_0_resume
    addi a0, a0, 99
priority_fence_0_resume:
    CHECK a0, 0
priority_fence_1:
    fence.i
    nop
priority_fence_1_branch:
    beq zero, zero, priority_fence_1_resume
    addi a0, a0, 99
priority_fence_1_resume:
    CHECK a0, 0
#ifndef SPIKE_SMOKE
    li t0, 0x800
    csrw mie, t0
    csrsi mstatus, 8
    li t2, 0
    EXPECT 0x8000000b, t2, priority_irq, priority_irq_resume
priority_irq:
    addi a7, zero, 1
    nop
priority_irq_branch:
    beq zero, zero, priority_irq_wrong
priority_irq_wrong:
    addi a0, a0, 99
priority_irq_resume:
    csrw mie, zero
    CHECK a0, 0
#endif
    FINISH
