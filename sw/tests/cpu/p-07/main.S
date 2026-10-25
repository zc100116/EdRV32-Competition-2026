/* File: p-07/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: I$ 缺失后端继续、D$ 缺失冻结 M 及之前。
 * Clock: clk_sys. */
#include "test.h"
    START
    la a0, scratch
    li a1, 0
    .balign 8
ic_window:
    addi a1, a1, 1
    addi a1, a1, 1
    addi a1, a1, 1
    addi a1, a1, 1
ic_miss:
    addi a1, a1, 1
dc_miss:
    lw a2, 0(a0)
    addi a1, a1, 1
    CHECK a1, 6
    CHECK a2, 0
    FINISH
