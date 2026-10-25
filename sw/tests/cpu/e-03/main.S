/* File: e-03/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 五种到达窗口的外部中断，处理程序记录 mepc 并检查无重复/遗漏。
 * Clock: clk_sys. */
#include "test.h"
    START
    li s0, 0
    li a0, 0
    li a1, 100
    li a2, 7
    la a3, scratch
    la t0, irq_handler
    csrw mtvec, t0
    li t0, 0x800
    csrw mie, t0
    li t0, 8
    csrs mstatus, t0
irq_resume:
irq_ordinary:
    addi a0, a0, 1
irq_division:
    div a4, a1, a2
    CHECK a4, 14
    addi a0, a0, 1
#ifndef SPIKE_SMOKE
    la a5, device_registers
irq_device:
    lw a4, 0(a5)
#endif
    addi a0, a0, 1
irq_dc_miss:
    lw a4, 0(a3)
    addi a0, a0, 1
irq_redirect:
    beq zero, zero, irq_redirect_target
    addi a0, a0, 100
irq_redirect_target:
    addi a0, a0, 1
irq_end:
    csrw mie, zero
    CHECK a0, 5
#ifndef SPIKE_SMOKE
    CHECK s0, 5
#else
    CHECK s0, 0
#endif

    j irq_done
    .balign 4
irq_handler:
    IRQ_SAVE
    csrr t0, mcause
    li t1, 0x8000000b
    bne t0, t1, fail
    csrr t0, mepc
    la t1, irq_resume
    bltu t0, t1, fail
    la t1, irq_end
    bgeu t0, t1, fail
    csrr t0, mstatus
    andi t0, t0, 0x88
    CHECK t0, 0x80
    addi s0, s0, 1
    csrr t0, mepc
    la t1, irq_record
    slli t2, s0, 3
    add t1, t1, t2
    sw t0, -8(t1)
    csrr t0, mcause
    sw t0, -4(t1)
    IRQ_RESTORE
    mret
irq_done:

.section .data
irq_record: .fill 5,8,0
.section .text
.section .data
.balign 16
    DEVICE_DATA
.section .text
    FINISH
