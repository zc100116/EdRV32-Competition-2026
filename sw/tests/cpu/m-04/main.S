/* File: m-04/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 执行旧代码后改写为返回42，FENCE.I 后必须执行新字节。
 * Clock: clk_sys. */
#include "test.h"
    START
#ifdef FENCEI_IRQ
    li s0, 0
    la t0, fence_irq_handler
    csrw mtvec, t0
    li t0, 0x800
    csrw mie, t0
    li t0, 8
    csrs mstatus, t0
#endif
    jal ra, modified_code
    CHECK a0, 1
    la a1, modified_code
    li a2, 0x02a00513
    sw a2, 0(a1)
self_modify_fence:
    fence.i
fence_irq_resume:
    jal ra, modified_code
    CHECK a0, 42
#ifdef FENCEI_IRQ
    CHECK s0, 1
#endif
    j self_modify_done
    .balign 8
modified_code:
    addi a0, zero, 1
    ret
#ifdef FENCEI_IRQ
    .balign 4
fence_irq_handler:
    IRQ_SAVE
    csrr t0, mcause
    li t1, 0x8000000b
    bne t0, t1, fail
    csrr t0, mepc
    la t1, fence_irq_resume
    bne t0, t1, fail
    addi s0, s0, 1
    IRQ_RESTORE
    mret
#endif
self_modify_done:
    FINISH
