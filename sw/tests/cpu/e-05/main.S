/* File: e-05/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: direct 入口、vectored 同步异常 BASE、外部中断 BASE+4×11。
 * Clock: clk_sys. */
#include "test.h"
    START
    li s0, 0
    la t0, direct_entry
    csrw mtvec, t0
    ecall
    CHECK s0, 1
    la t0, vector_table
    ori t0, t0, 1
    csrw mtvec, t0
    ecall
    CHECK s0, 2
#ifndef SPIKE_SMOKE
    li t0, 0x800
    csrw mie, t0
    li t0, 8
    csrs mstatus, t0
vector_irq_window:
    li t0, 3
vector_wait:
    bltu s0, t0, vector_wait
    csrw mie, zero
#endif
    j vector_done
    .balign 64
vector_table:
    j vector_sync
    .rept 10
    j fail
    .endr
    j vector_mei
vector_sync:
    li a0, 2
    j vector_handler
direct_entry:
    li a0, 1
vector_handler:
    addi s0, s0, 1
    bne a0, s0, fail
    csrr t0, mcause
    CHECK t0, 11
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
vector_mei:
    IRQ_SAVE
    addi s0, s0, 1
    csrr t0, mcause
    CHECK t0, 0x8000000b
    IRQ_RESTORE
    mret
vector_done:
    FINISH
