/* File: b-05/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 老 M 级访问异常与年轻 E/D 重定向竞争。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    la a1, scratch
#ifndef SPIKE_SMOKE
    li t2, 0
    EXPECT 5, a1, oldest_fault, priority_resume
    .balign 8
oldest_fault:
    lw a2, 0(a1)
    nop                         # Keep the faulting load in an older issue group.
priority_branch:
    beq zero, zero, wrong_target
priority_jal:
    jal zero, wrong_target
wrong_target:
    addi a0, a0, 100
priority_resume:
#endif
    CHECK a0, 0
    FINISH
