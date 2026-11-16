/* trap.S — T-VIS-RTOS RV32IM M-mode trap; clk_sys.
 * Keep the official context layout; bracket save/dispatch/restore with CLINT time.
 */
#include "portContext.h"
.section .text.showcase_rtos_trap,"ax",@progbits
.balign 4
.global showcase_rtos_trap
showcase_rtos_trap:
    addi sp, sp, -16
    sw t0, 0(sp)
    sw t1, 4(sp)
    la t0, sched_mtime_low
    lw t0, 0(t0)
    lw t0, 0(t0)
    la t1, sched_kernel_entry
    sw t0, 0(t1)
    lw t0, 0(sp)
    lw t1, 4(sp)
    addi sp, sp, 16
    portcontextSAVE_CONTEXT_INTERNAL
    csrr a0, mcause
    csrr a1, mepc
    bltz a0, 1f
    addi a1, a1, 4
1:
    sw a1, 0(sp)
    load_x sp, xISRStackTop
    call sched_trap_dispatch
    call sched_trap_finish
    la t1, pxCurrentTCB
    lw t1, 0(t1)
    lw sp, 0(t1)
    lw t0, 0(sp)
    csrw mepc, t0
    lw t0, 4(sp)
    csrw mstatus, t0
    lw t0, 120(sp)
    la t1, xCriticalNesting
    sw t0, 0(t1)
    lw x1, 8(sp)
    lw x8, 24(sp)
    lw x9, 28(sp)
    lw x10, 32(sp)
    lw x11, 36(sp)
    lw x12, 40(sp)
    lw x13, 44(sp)
    lw x14, 48(sp)
    lw x15, 52(sp)
    lw x16, 56(sp)
    lw x17, 60(sp)
    lw x18, 64(sp)
    lw x19, 68(sp)
    lw x20, 72(sp)
    lw x21, 76(sp)
    lw x22, 80(sp)
    lw x23, 84(sp)
    lw x24, 88(sp)
    lw x25, 92(sp)
    lw x26, 96(sp)
    lw x27, 100(sp)
    lw x28, 104(sp)
    lw x29, 108(sp)
    lw x30, 112(sp)
    lw x31, 116(sp)

    /* The final CLINT time sample includes restoration; update cumulative clocks. */
    la t2, sched_mtime_low
    lw t2, 0(t2)
    lw t2, 0(t2)
    la t1, sched_restore_entry
    lw t1, 0(t1)
    sub t2, t2, t1
    la t1, sched_kernel_cycles
    lw t0, 0(t1)
    add t0, t0, t2
    sw t0, 0(t1)
    la t1, sched_interrupt_cycles
    lw t0, 0(t1)
    add t0, t0, t2
    sw t0, 0(t1)
    lw t0, 12(sp)
    lw t1, 16(sp)
    lw t2, 20(sp)
    addi sp, sp, 124
    mret

.section .text.sched_install_trap,"ax",@progbits
.balign 4
.global sched_install_trap
sched_install_trap:
    la t0, showcase_rtos_trap
    csrw mtvec, t0
    ret
