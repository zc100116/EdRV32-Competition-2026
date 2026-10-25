/* File: p-05/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 迭代除法全流水停顿、相邻依赖及特殊情况直接结果。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 100
    li a1, 7
    .balign 8
div_begin:
    div a2, a0, a1
    addi a3, a2, 1
    CHECK a3, 15
    rem a2, a0, a1
    CHECK a2, 2
    divu a2, a0, zero
    CHECK a2, -1
    li a0, 0x80000000
    li a1, -1
    div a2, a0, a1
    CHECK a2, 0x80000000
    FINISH
