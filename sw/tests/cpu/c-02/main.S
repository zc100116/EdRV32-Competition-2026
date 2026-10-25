/* File: c-02/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: minstret 按双退休加2，CY/IR/HPM inhibit 独立停止并支持64位写入。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a3, 0
#ifndef SPIKE_SMOKE
    li a0, 0x7fd
    csrw mcountinhibit, a0
    li a1, 123
    csrw mcycle, a1
    csrw minstret, a1
    csrw 0xb03, a1
    csrw 0xb04, a1
    csrw 0xb05, a1
    csrw 0xb06, a1
    csrw 0xb07, a1
    csrw 0xb08, a1
    csrw 0xb09, a1
    csrw 0xb0a, a1
    li a2, 2
    csrw 0x323, a2
    .rept 8
    addi a3, a3, 1
    .endr
    csrr a4, mcycle
    CHECK a4, 123
    csrr a4, minstret
    CHECK a4, 123
    csrr a4, 0xb03
    CHECK a4, 123
    csrr a4, 0xb04
    CHECK a4, 123
    csrr a4, 0xb05
    CHECK a4, 123
    csrr a4, 0xb06
    CHECK a4, 123
    csrr a4, 0xb07
    CHECK a4, 123
    csrr a4, 0xb08
    CHECK a4, 123
    csrr a4, 0xb09
    CHECK a4, 123
    csrr a4, 0xb0a
    CHECK a4, 123
    csrw minstret, zero
    csrw minstreth, zero
    li a0, 0x7f9
retire_enable:
    csrw mcountinhibit, a0
    .balign 8
dual_retire_begin:
    addi a1, zero, 1
    addi a2, zero, 2
    addi a3, zero, 3
    addi a4, zero, 4
    li a0, 0x7fd
retire_disable:
    csrw mcountinhibit, a0
    csrr a4, minstret
    la a0, expected_instret
    lw a1, 0(a0)
    bne a4, a1, fail
    csrr a4, minstreth
    CHECK a4, 0
    li a1, -1
    csrw mcycle, a1
    csrw mcycleh, a1
    csrr a2, cycle
    bne a1, a2, fail
    csrr a2, cycleh
    bne a1, a2, fail
    li a0, 0x7fc
    csrw mcountinhibit, a0
    li a1, 456
cycle_write_collision:
    csrw mcycle, a1
    li a0, 0x7fd
    csrw mcountinhibit, a0
#endif
    .section .data
    .globl expected_instret
expected_instret: .word 0
    .section .text
    FINISH
