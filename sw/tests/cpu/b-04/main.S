/* File: b-04/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 六层嵌套调用超过四项 RAS，按实际链接返回。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    jal ra, call_0
    CHECK a0, 6
    j calls_done
call_0:
    mv s0, ra
    addi a0, a0, 1
    jal ra, call_1
    mv ra, s0
    ret
call_1:
    mv s1, ra
    addi a0, a0, 1
    jal ra, call_2
    mv ra, s1
    ret
call_2:
    mv s2, ra
    addi a0, a0, 1
    jal ra, call_3
    mv ra, s2
    ret
call_3:
    mv s3, ra
    addi a0, a0, 1
    jal ra, call_4
    mv ra, s3
    ret
call_4:
    mv s4, ra
    addi a0, a0, 1
    jal ra, call_5
    mv ra, s4
    ret
call_5:
    mv s5, ra
    addi a0, a0, 1
    mv ra, s5
    ret
calls_done:
    FINISH
