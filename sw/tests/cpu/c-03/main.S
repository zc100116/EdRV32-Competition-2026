/* File: c-03/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 事件0–31逐个精确计数，保留事件不计数。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0x7fd
    csrw mcountinhibit, a0
    la a6, expected_hpm
    la a7, observed_hpm
    li a4, 0
    li a5, 1
    li a0, 0
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_0_begin:
    csrw mcountinhibit, a0
    j hpm_0_single
.balign 8
    nop
hpm_0_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_0_branch
    jal zero, hpm_0_branch
hpm_0_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_0_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 0(a7)
#ifndef SPIKE_SMOKE
    lw a2, 0(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 1
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_1_begin:
    csrw mcountinhibit, a0
    j hpm_1_single
.balign 8
    nop
hpm_1_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_1_branch
    jal zero, hpm_1_branch
hpm_1_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_1_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 4(a7)
#ifndef SPIKE_SMOKE
    lw a2, 4(a6)
    bne a1, a2, fail
#endif
    li a0, 2
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_2_begin:
    csrw mcountinhibit, a0
    j hpm_2_single
.balign 8
    nop
hpm_2_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_2_branch
    jal zero, hpm_2_branch
hpm_2_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_2_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 8(a7)
#ifndef SPIKE_SMOKE
    lw a2, 8(a6)
    bne a1, a2, fail
#endif
    li a0, 3
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_3_begin:
    csrw mcountinhibit, a0
    j hpm_3_single
.balign 8
    nop
hpm_3_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_3_branch
    jal zero, hpm_3_branch
hpm_3_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_3_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 12(a7)
#ifndef SPIKE_SMOKE
    lw a2, 12(a6)
    bne a1, a2, fail
#endif
    li a0, 4
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_4_begin:
    csrw mcountinhibit, a0
    j hpm_4_single
.balign 8
    nop
hpm_4_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_4_branch
    jal zero, hpm_4_branch
hpm_4_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_4_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 16(a7)
#ifndef SPIKE_SMOKE
    lw a2, 16(a6)
    bne a1, a2, fail
#endif
    li a0, 5
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_5_begin:
    csrw mcountinhibit, a0
    j hpm_5_single
.balign 8
    nop
hpm_5_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_5_branch
    jal zero, hpm_5_branch
hpm_5_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_5_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 20(a7)
#ifndef SPIKE_SMOKE
    lw a2, 20(a6)
    bne a1, a2, fail
#endif
    li a0, 6
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_6_begin:
    csrw mcountinhibit, a0
    j hpm_6_single
.balign 8
    nop
hpm_6_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_6_branch
    jal zero, hpm_6_branch
hpm_6_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_6_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 24(a7)
#ifndef SPIKE_SMOKE
    lw a2, 24(a6)
    bne a1, a2, fail
#endif
    li a0, 7
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_7_begin:
    csrw mcountinhibit, a0
    j hpm_7_single
.balign 8
    nop
hpm_7_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_7_branch
    jal zero, hpm_7_branch
hpm_7_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_7_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 28(a7)
#ifndef SPIKE_SMOKE
    lw a2, 28(a6)
    bne a1, a2, fail
#endif
    li a0, 8
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_8_begin:
    csrw mcountinhibit, a0
    j hpm_8_single
.balign 8
    nop
hpm_8_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_8_branch
    jal zero, hpm_8_branch
hpm_8_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_8_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 32(a7)
#ifndef SPIKE_SMOKE
    lw a2, 32(a6)
    bne a1, a2, fail
#endif
    li a0, 9
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_9_begin:
    csrw mcountinhibit, a0
    j hpm_9_single
.balign 8
    nop
hpm_9_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_9_branch
    jal zero, hpm_9_branch
hpm_9_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_9_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 36(a7)
#ifndef SPIKE_SMOKE
    lw a2, 36(a6)
    bne a1, a2, fail
#endif
    li a0, 10
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_10_begin:
    csrw mcountinhibit, a0
    j hpm_10_single
.balign 8
    nop
hpm_10_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_10_branch
    jal zero, hpm_10_branch
hpm_10_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_10_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 40(a7)
#ifndef SPIKE_SMOKE
    lw a2, 40(a6)
    bne a1, a2, fail
#endif
    li a0, 11
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_11_begin:
    csrw mcountinhibit, a0
    j hpm_11_single
.balign 8
    nop
hpm_11_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_11_branch
    jal zero, hpm_11_branch
hpm_11_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_11_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 44(a7)
#ifndef SPIKE_SMOKE
    lw a2, 44(a6)
    bne a1, a2, fail
#endif
    li a0, 12
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_12_begin:
    csrw mcountinhibit, a0
    j hpm_12_single
.balign 8
    nop
hpm_12_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_12_branch
    jal zero, hpm_12_branch
hpm_12_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_12_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 48(a7)
#ifndef SPIKE_SMOKE
    lw a2, 48(a6)
    bne a1, a2, fail
#endif
    li a0, 13
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_13_begin:
    csrw mcountinhibit, a0
    j hpm_13_single
.balign 8
    nop
hpm_13_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_13_branch
    jal zero, hpm_13_branch
hpm_13_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_13_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 52(a7)
#ifndef SPIKE_SMOKE
    lw a2, 52(a6)
    bne a1, a2, fail
#endif
    li a0, 14
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_14_begin:
    csrw mcountinhibit, a0
    j hpm_14_single
.balign 8
    nop
hpm_14_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_14_branch
    jal zero, hpm_14_branch
hpm_14_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_14_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 56(a7)
#ifndef SPIKE_SMOKE
    lw a2, 56(a6)
    bne a1, a2, fail
#endif
    li a0, 15
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_15_begin:
    csrw mcountinhibit, a0
    j hpm_15_single
.balign 8
    nop
hpm_15_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_15_branch
    jal zero, hpm_15_branch
hpm_15_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_15_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 60(a7)
#ifndef SPIKE_SMOKE
    lw a2, 60(a6)
    bne a1, a2, fail
#endif
    li a0, 16
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_16_begin:
    csrw mcountinhibit, a0
    j hpm_16_single
.balign 8
    nop
hpm_16_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_16_branch
    jal zero, hpm_16_branch
hpm_16_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_16_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 64(a7)
#ifndef SPIKE_SMOKE
    lw a2, 64(a6)
    bne a1, a2, fail
#endif
    li a0, 17
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_17_begin:
    csrw mcountinhibit, a0
    j hpm_17_single
.balign 8
    nop
hpm_17_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_17_branch
    jal zero, hpm_17_branch
hpm_17_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_17_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 68(a7)
#ifndef SPIKE_SMOKE
    lw a2, 68(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 18
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_18_begin:
    csrw mcountinhibit, a0
    j hpm_18_single
.balign 8
    nop
hpm_18_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_18_branch
    jal zero, hpm_18_branch
hpm_18_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_18_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 72(a7)
#ifndef SPIKE_SMOKE
    lw a2, 72(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 19
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_19_begin:
    csrw mcountinhibit, a0
    j hpm_19_single
.balign 8
    nop
hpm_19_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_19_branch
    jal zero, hpm_19_branch
hpm_19_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_19_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 76(a7)
#ifndef SPIKE_SMOKE
    lw a2, 76(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 20
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_20_begin:
    csrw mcountinhibit, a0
    j hpm_20_single
.balign 8
    nop
hpm_20_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_20_branch
    jal zero, hpm_20_branch
hpm_20_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_20_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 80(a7)
#ifndef SPIKE_SMOKE
    lw a2, 80(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 21
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_21_begin:
    csrw mcountinhibit, a0
    j hpm_21_single
.balign 8
    nop
hpm_21_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_21_branch
    jal zero, hpm_21_branch
hpm_21_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_21_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 84(a7)
#ifndef SPIKE_SMOKE
    lw a2, 84(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 22
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_22_begin:
    csrw mcountinhibit, a0
    j hpm_22_single
.balign 8
    nop
hpm_22_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_22_branch
    jal zero, hpm_22_branch
hpm_22_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_22_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 88(a7)
#ifndef SPIKE_SMOKE
    lw a2, 88(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 23
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_23_begin:
    csrw mcountinhibit, a0
    j hpm_23_single
.balign 8
    nop
hpm_23_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_23_branch
    jal zero, hpm_23_branch
hpm_23_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_23_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 92(a7)
#ifndef SPIKE_SMOKE
    lw a2, 92(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 24
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_24_begin:
    csrw mcountinhibit, a0
    j hpm_24_single
.balign 8
    nop
hpm_24_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_24_branch
    jal zero, hpm_24_branch
hpm_24_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_24_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 96(a7)
#ifndef SPIKE_SMOKE
    lw a2, 96(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 25
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_25_begin:
    csrw mcountinhibit, a0
    j hpm_25_single
.balign 8
    nop
hpm_25_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_25_branch
    jal zero, hpm_25_branch
hpm_25_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_25_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 100(a7)
#ifndef SPIKE_SMOKE
    lw a2, 100(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 26
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_26_begin:
    csrw mcountinhibit, a0
    j hpm_26_single
.balign 8
    nop
hpm_26_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_26_branch
    jal zero, hpm_26_branch
hpm_26_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_26_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 104(a7)
#ifndef SPIKE_SMOKE
    lw a2, 104(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 27
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_27_begin:
    csrw mcountinhibit, a0
    j hpm_27_single
.balign 8
    nop
hpm_27_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_27_branch
    jal zero, hpm_27_branch
hpm_27_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_27_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 108(a7)
#ifndef SPIKE_SMOKE
    lw a2, 108(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 28
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_28_begin:
    csrw mcountinhibit, a0
    j hpm_28_single
.balign 8
    nop
hpm_28_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_28_branch
    jal zero, hpm_28_branch
hpm_28_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_28_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 112(a7)
#ifndef SPIKE_SMOKE
    lw a2, 112(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 29
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_29_begin:
    csrw mcountinhibit, a0
    j hpm_29_single
.balign 8
    nop
hpm_29_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_29_branch
    jal zero, hpm_29_branch
hpm_29_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_29_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 116(a7)
#ifndef SPIKE_SMOKE
    lw a2, 116(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 30
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_30_begin:
    csrw mcountinhibit, a0
    j hpm_30_single
.balign 8
    nop
hpm_30_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_30_branch
    jal zero, hpm_30_branch
hpm_30_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_30_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 120(a7)
#ifndef SPIKE_SMOKE
    lw a2, 120(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
    li a0, 31
    csrw 0x323, a0
    csrw 0xb03, zero
    csrw 0xb83, zero
    li a0, 0x7f5
hpm_31_begin:
    csrw mcountinhibit, a0
    j hpm_31_single
.balign 8
    nop
hpm_31_single:
    addi a1, zero, 10
    addi a2, zero, 20
    add a3, a1, a2
    add a4, a3, a2
    la t3, scratch
    sw a4, 0(t3)
    lw a3, 0(t3)
    add a4, a3, a2
    li a1, 100
    li a2, 7
    div a3, a1, a2
    beq a1, a2, hpm_31_branch
    jal zero, hpm_31_branch
hpm_31_branch:
#ifndef SPIKE_SMOKE
    la t3, device_registers
    lw a3, 0(t3)
#endif
    li a0, 0x7fd
hpm_31_freeze:
    csrw mcountinhibit, a0
    csrr a1, 0xb03
    sw a1, 124(a7)
#ifndef SPIKE_SMOKE
    lw a2, 124(a6)
    bne a1, a2, fail
#endif
    CHECK a1, 0
.section .data
.globl expected_hpm
expected_hpm: .fill 32,4,0
.globl observed_hpm
observed_hpm: .fill 32,4,0
    DEVICE_DATA
.section .text
    FINISH
