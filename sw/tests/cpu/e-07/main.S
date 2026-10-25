/* File: e-07/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 异常进入保存 MIE，MRET 恢复 MIE/MPIE 并返回指定 mepc。
 * Clock: clk_sys. */
#include "test.h"
    START
    la t0, mret_handler
    csrw mtvec, t0
    li t0, 8
    csrs mstatus, t0
mret_ecall:
    ecall
mret_resume:
    csrr t0, mstatus
    andi t0, t0, 0x88
    CHECK t0, 0x88
    j mret_done
    .balign 4
mret_handler:
    csrr t0, mepc
    la t1, mret_ecall
    bne t0, t1, fail
    csrr t0, mstatus
    andi t0, t0, 0x88
    CHECK t0, 0x80
    la t0, mret_resume
    csrw mepc, t0
    mret
mret_done:
    FINISH
