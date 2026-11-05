/* File: a-02/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan A-02.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a1, 0x11223344
    sw a1, 0(a4)
    fence
fallback_miss:
    lw a3, 0(a4)
    addi a5, a3, 1
    CHECK a5, 0x11223345
fallback_ready:
    lw a3, 0(a4)
    addi a5, a3, 1
    CHECK a5, 0x11223345
    li a2, 0x55
    sb a2, 1(a4)
fallback_byte:
    lw a3, 0(a4)
    addi a5, a3, 1
    CHECK a5, 0x11225545
    li a2, 0x6677
    sh a2, 2(a4)
fallback_half:
    lw a3, 0(a4)
    addi a5, a3, 1
    CHECK a5, 0x66775545
    DEVICE_DATA
    la a4, device_registers
    li a1, 23
    sw a1, 0(a4)
fallback_device:
    lw a3, 0(a4)
    addi a5, a3, 1
    CHECK a5, 24
    FINISH
