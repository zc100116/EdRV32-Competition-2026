/* File: b-12/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 周期2/3局部分支与独立全局噪声；冲刷分支不训练任何表。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a3, 0
    li a4, 8192
    li s5, 1
    li a5, 0
    li a6, 3
    .balign 8
pattern_loop:
    andi a7, a3, 1
    .balign 8
period_two:
    beqz a7, two_done
    addi zero, zero, 0
two_done:
    addi a5, a5, 1
    .balign 8
period_three:
    bne a5, a6, three_done
    li a5, 0
three_done:
    /* Xorshift32 supplies independent global history between local patterns. */
    slli s6, s5, 13
    xor s5, s5, s6
    srli s6, s5, 17
    xor s5, s5, s6
    slli s6, s5, 5
    xor s5, s5, s6
    andi s6, s5, 1
    .balign 8
noise_branch:
    beqz s6, noise_done
    addi zero, zero, 0
noise_done:
    addi a3, a3, 1
    blt a3, a4, pattern_loop
    li a0, 0
    li a1, 16
    li a2, 0
    .balign 8
flush_outer:
    beq zero, zero, flush_target
flushed_branch:
    bne a0, a1, pollution
pollution:
    addi a2, a2, 100
flush_target:
    addi a0, a0, 1
    blt a0, a1, flush_outer
    CHECK a0, 16
    CHECK a2, 0
probe_branch:
    beq a0, a1, probe_done
    j fail
probe_done:
    FINISH
