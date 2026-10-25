/* File: test.h; Spec: cpu-spec 4.5, 5; Description: Directed-test checks,
 * precise trap expectations and HTIF termination. Clock: clk_sys. */
.option norvc
.option norelax

.macro CHECK reg, value
    li t5, \value
    bne \reg, t5, fail
.endm

/* Interrupt tests reserve s1–s4 for preserving the handler's scratch registers. */
.macro IRQ_SAVE
    mv s1, t0
    mv s2, t1
    mv s3, t2
    mv s4, t5
.endm

.macro IRQ_RESTORE
    mv t0, s1
    mv t1, s2
    mv t2, s3
    mv t5, s4
.endm

/* The synthetic B1 bank is outside cacheable SRAM/DDR; Spike uses backing RAM. */
.macro DEVICE_DATA
    .section .data
    .balign 16
    .globl device_registers
#ifdef SPIKE_SMOKE
device_registers: .fill 4,4,0
#else
    .equ device_registers, 0x40000000
#endif
    .section .text
.endm

.macro START
    .section .text.init,"ax",@progbits
    .globl _start
_start:
    li gp, 1
    la t0, unexpected_trap
    csrw mtvec, t0
    csrw mie, zero
    csrw mstatus, zero
.endm

/* Set the expected architectural trap tuple before a labelled fault. */
.macro EXPECT cause, value, fault, resume
    li s8, \cause
    mv s9, \value
#ifdef SPIKE_SMOKE
    /* Spike reports breakpoint PC; cpu-spec 5 requires zero for EBREAK. */
    .if \cause == 3
    la s9, \fault
    .endif
#endif
    la s10, \fault
    la s11, \resume
    csrr s7, mstatus
    andi s7, s7, 8
    slli s7, s7, 4
    la t0, expected_trap
    csrw mtvec, t0
.endm

.macro FINISH
    j pass
    .balign 4
expected_trap:
    csrr t0, mcause
    bne t0, s8, fail
    csrr t0, mtval
    bne t0, s9, fail
    csrr t0, mepc
    bne t0, s10, fail
    csrr t0, mstatus
    andi t1, t0, 8
    bnez t1, fail
    andi t1, t0, 0x80
    bne t1, s7, fail
    li t1, 0x1800
    and t0, t0, t1
    bne t0, t1, fail
    csrw mepc, s11
    mret
unexpected_trap:
    li gp, 0x7f
fail:
    slli gp, gp, 1
    ori gp, gp, 1
    la t0, tohost
    sw gp, 0(t0)
1:  j 1b
pass:
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
2:  j 2b
    .section .tohost,"aw",@progbits
    .balign 64
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
    .section .data,"aw",@progbits
    .balign 16
    .globl scratch
scratch: .fill 64,4,0
.endm
