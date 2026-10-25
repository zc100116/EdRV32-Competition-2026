/* File: m-01/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 较老异常冲刷设备访问，禁止任何设备副作用。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    li t2, -1
    EXPECT 2, t2, before_device, no_device_resume
    la a2, device_registers
before_device:
    .word 0xffffffff
forbidden_device_load:
    lw a0, 0(a2)
forbidden_device_store:
    sw a0, 4(a2)
no_device_resume:
    CHECK a0, 0
    li t2, -1
    EXPECT 2, t2, before_device_store, no_store_resume
before_device_store:
    .word 0xffffffff
forbidden_immediate_store:
    sw a0, 4(a2)
no_store_resume:
    CHECK a0, 0
.section .data
.balign 16
    DEVICE_DATA
.section .text
    FINISH
