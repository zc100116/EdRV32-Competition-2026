/* File: e-01/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 逐个检查取指错误、非法指令、断点、不对齐、访问错误及 M 态 ECALL。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a1, 0
    li t2, 0
    li t0, 8
    csrs mstatus, t0
    EXPECT 11, t2, fault_ecall, after_ecall
fault_ecall:
    ecall
after_ecall:
    csrr t0, mstatus
    andi t0, t0, 0x88
    CHECK t0, 0x88
    li t2, 0
    EXPECT 3, t2, fault_ebreak, after_ebreak
fault_ebreak:
    ebreak
after_ebreak:
    li t2, -1
    EXPECT 2, t2, fault_illegal, after_illegal
fault_illegal:
.word 0xffffffff
after_illegal:
    la a0, scratch
    addi a0, a0, 1
    EXPECT 4, a0, fault_load_align, after_load_align
fault_load_align:
    lw a1, 0(a0)
after_load_align:
    EXPECT 6, a0, fault_store_align, after_store_align
fault_store_align:
    sw a1, 0(a0)
after_store_align:
#ifndef SPIKE_SMOKE
    la a0, fault_fetch
    EXPECT 1, a0, fault_fetch, after_fetch
    j fault_fetch
.balign 8
fault_fetch:
    nop
    j fail
after_fetch:
#endif
#ifndef SPIKE_SMOKE
    la a0, scratch
    EXPECT 5, a0, fault_load, after_load
fault_load:
    lw a1, 0(a0)
after_load:
#endif
#ifndef SPIKE_SMOKE
    la a0, scratch
    EXPECT 7, a0, fault_store, after_store
fault_store:
    sw a1, 0(a0)
after_store:
#endif
#ifdef RVC_DISABLED
    la t2, halfword_target
    EXPECT 0, t2, fault_jump_align, after_jump_align
    la a0, halfword_target
fault_jump_align:
    jalr zero, 0(a0)
    j fail
    .balign 4
    .hword 0x0001
halfword_target:
    .hword 0x0001
after_jump_align:
#endif
    FINISH
