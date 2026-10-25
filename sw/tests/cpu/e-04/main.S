/* File: e-04/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: MEI、MSI、MTI 同时等待时按标准优先级服务。
 * Clock: clk_sys. */
#include "test.h"
    START
    li s0, 0
    la t0, priority_handler
    csrw mtvec, t0
    li t0, 0x888
    csrw mie, t0
    li t0, 8
    csrs mstatus, t0
irq_priority_window:
#ifndef SPIKE_SMOKE
    li t0, 3
priority_wait:
    bltu s0, t0, priority_wait
#endif
    csrw mie, zero
    j priority_done
    .balign 4
priority_handler:
    IRQ_SAVE
    csrr t0, mcause
    slli t1, s0, 2
    la t2, priority_causes
    add t2, t2, t1
    lw t1, 0(t2)
    bne t0, t1, fail
    addi s0, s0, 1
    IRQ_RESTORE
    mret
priority_done:
#ifndef SPIKE_SMOKE
    CHECK s0, 3
#endif
    .section .data
priority_causes: .word 0x8000000b, 0x80000003, 0x80000007
    .section .text
    FINISH
