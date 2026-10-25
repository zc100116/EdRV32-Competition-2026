/* File: e-02/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 异常在候选对第一/第二位置，检查老 ALU 精确提交。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    li t2, -1
    EXPECT 2, t2, first_fault, first_resume
    .balign 8
first_fault:
    .word 0xffffffff
    addi a0, a0, 100
first_resume:
    CHECK a0, 0
    EXPECT 2, t2, second_fault, second_resume
    .balign 8
older_alu:
    addi a0, a0, 1
second_fault:
    .word 0xffffffff
    addi a0, a0, 100
second_resume:
    CHECK a0, 1
    FINISH
