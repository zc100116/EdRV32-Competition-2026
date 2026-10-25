/* File: e-08/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 设备 store 响应错误的精确异常与年轻副作用取消。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 1
    li a1, 0
#ifndef SPIKE_SMOKE
    la a2, device_registers
    EXPECT 7, a2, device_error_store, device_error_resume
    addi a0, a0, 1
device_error_store:
    sw a0, 0(a2)
    addi a1, a1, 100
    sw a0, 4(a2)
device_error_resume:
    CHECK a0, 2
    CHECK a1, 0
#endif
.section .data
.balign 16
    DEVICE_DATA
.section .text
    FINISH
