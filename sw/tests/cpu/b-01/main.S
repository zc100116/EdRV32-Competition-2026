/* File: b-01/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 冷分支方向误预测，年轻槽 1 和顺序路径无副作用。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    li a1, 1
    .balign 8
branch_direction:
    beq a1, a1, taken
    addi a0, a0, 99
    addi a0, a0, 77
taken:
    CHECK a0, 0
    li a2, 8
branch_loop:
    addi a0, a0, 1
    addi a2, a2, -1
    bnez a2, branch_loop
    CHECK a0, 8
    FINISH
