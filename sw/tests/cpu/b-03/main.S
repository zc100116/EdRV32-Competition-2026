/* File: b-03/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 冷 BTB 的 JAL 在 D 级计算目标并重定向。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
cold_jal:
    jal ra, cold_target
    addi a0, a0, 100
cold_target:
    addi a0, a0, 1
    la t0, cold_jal
    addi t0, t0, 4
    bne ra, t0, fail
    CHECK a0, 1
    FINISH
