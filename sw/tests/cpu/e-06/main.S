/* File: e-06/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: WFI 在 MIE=0 被使能中断唤醒，MIE=1 时进入处理。
 * Clock: clk_sys. */
#include "test.h"
    START
    li s0, 0
    la t0, wfi_handler
    csrw mtvec, t0
    li t0, 8
    csrw mie, t0
wfi_mie_zero:
#ifndef SPIKE_SMOKE
    wfi
#else
    nop
#endif
wfi_wake_zero:
    CHECK s0, 0
    li t0, 8
    csrs mstatus, t0
wfi_mie_one:
#ifndef SPIKE_SMOKE
    wfi
#else
    nop
#endif
wfi_wake_one:
#ifndef SPIKE_SMOKE
    CHECK s0, 1
#endif
    csrw mie, zero
    j wfi_done
    .balign 4
wfi_handler:
    IRQ_SAVE
    csrr t0, mcause
    CHECK t0, 0x80000003
    addi s0, s0, 1
    IRQ_RESTORE
    mret
wfi_done:
    FINISH
