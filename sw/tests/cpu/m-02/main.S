/* File: m-02/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 设备写非推送，响应前后续指令不得退休。
 * Clock: clk_sys. */
#include "test.h"
    START
    la a0, device_registers
    li a1, 0x31415926
    li a2, 0
posted_store:
    sw a1, 0(a0)
after_device_store:
    addi a2, a2, 1
    lw a3, 0(a0)
    bne a3, a1, fail
    CHECK a2, 1
.section .data
.balign 16
    DEVICE_DATA
.section .text
    FINISH
