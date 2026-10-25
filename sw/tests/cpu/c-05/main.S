/* File: c-05/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 组合配对、误预测和异常路径逐位检查 debug_o。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    .balign 8
debug_pair:
    addi a1, zero, 3
    addi a2, zero, 4
    add a3, a1, a2
    li t2, -1
    EXPECT 2, t2, debug_fault, debug_resume
debug_branch:
    beq zero, zero, debug_target
    addi a0, a0, 100
debug_target:
    .balign 8
debug_fault:
    .word 0xffffffff
debug_resume:
    CHECK a0, 0
    CHECK a3, 7
#ifndef SPIKE_SMOKE
    la a0, debug_errors
    lw a1, 0(a0)
    CHECK a1, 0
#endif
    .section .data
    .globl debug_errors
debug_errors: .word 0
    .section .text
    FINISH
