/* File: e-02/main.S; Spec: cpu-spec 4.2-4.5; cpu-testplan E-02.
 * Description: Check ordered slots across pipeline assignment.
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    la a4, scratch
    addi t2, a4, 1
    EXPECT 4, t2, fault_lmis, resume_0
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
older_0:
    addi a0, a0, 1
fault_lmis:
    lw a1, 1(a4)
    addi a0, a0, 100
resume_0:
    CHECK a0, 1
    addi t2, a4, 1
    EXPECT 6, t2, fault_smis, resume_1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
older_1:
    addi a0, a0, 1
fault_smis:
    sw a1, 1(a4)
    addi a0, a0, 100
resume_1:
    CHECK a0, 2
    addi t2, a4, 0
    EXPECT 5, t2, fault_lerr, resume_2
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
older_2:
    addi a0, a0, 1
fault_lerr:
#ifdef SPIKE_SMOKE
    j resume_2
#else
    lw a1, 0(a4)
#endif
    addi a0, a0, 100
resume_2:
    CHECK a0, 3
    addi t2, a4, 0
    EXPECT 7, t2, fault_serr, resume_3
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
older_3:
    addi a0, a0, 1
fault_serr:
#ifdef SPIKE_SMOKE
    j resume_3
#else
    sw a1, 0(a4)
#endif
    addi a0, a0, 100
resume_3:
    CHECK a0, 4
    la t2, fault_branch+2
    EXPECT 0, t2, fault_branch, resume_4
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
older_4:
    addi a0, a0, 1
fault_branch:
    beq zero, zero, fault_branch+2
    addi a0, a0, 100
resume_4:
    CHECK a0, 5
    la t2, fault_jal+2
    EXPECT 0, t2, fault_jal, resume_5
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
older_5:
    addi a0, a0, 1
fault_jal:
    jal a1, fault_jal+2
    addi a0, a0, 100
resume_5:
    CHECK a0, 6
    li t2, 1
    EXPECT 4, t2, both_older, both_resume
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
both_older:
    lw a1, 1(zero)
    beq zero, zero, both_younger+2
both_younger:
    nop
both_resume:
    CHECK a0, 6
    FINISH
