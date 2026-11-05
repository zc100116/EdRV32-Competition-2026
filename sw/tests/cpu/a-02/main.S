/* File: a-02/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan A-02.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a1, 0x11223344
    sw a1, 0(a4)
    sw a1, 4(a4)
    sw a1, 8(a4)
    sw a1, 12(a4)
    fence
fallback_miss:
    lw a3, 0(a4)
fallback_miss_consumer:
    addi a5, a3, 1
    CHECK a5, 0x11223345
fallback_ready:
    lw a3, 4(a4)
fallback_ready_consumer:
    addi a5, a3, 1
    CHECK a5, 0x11223345
    li a2, 0x55
held_byte_store:
    sb a2, 9(a4)
    nop
    nop
    nop
    nop
fallback_byte:
    lw a3, 8(a4)
fallback_byte_consumer:
    addi a5, a3, 1
    CHECK a5, 0x11225545
    li a2, 0x6677
    sh a2, 14(a4)
fallback_half:
    lw a3, 12(a4)
fallback_half_consumer:
    addi a5, a3, 1
    CHECK a5, 0x66773345
    /* A newly accepted M store also blocks an early query of its word. */
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
accepted_store_older:
    addi a6, zero, 0
    sw a1, 16(a4)
    addi a6, zero, 1
    addi a7, zero, 1
fallback_store:
    lw a3, 16(a4)
fallback_store_consumer:
    addi a5, a3, 1
    CHECK a5, 0x11223345
    li t2, 1
    EXPECT 4, t2, fallback_unaligned, fallback_unaligned_resume
fallback_unaligned:
    lw a3, 1(zero)
fallback_unaligned_younger:
    addi a5, a3, 1
fallback_unaligned_resume:
    DEVICE_DATA
    la a4, device_registers
    li a1, 23
    sw a1, 0(a4)
fallback_device:
    lw a3, 0(a4)
fallback_device_consumer:
    addi a5, a3, 1
    CHECK a5, 24
    FINISH
