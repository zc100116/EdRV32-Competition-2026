/* File: c-01/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 全部列举 CSR 的复位、读写、WARL、只读别名与非法访问。
 * Clock: clk_sys. */
#include "test.h"
.section .text.init,"ax",@progbits
.globl _start
_start:
    li gp, 1
#ifndef SPIKE_SMOKE
    csrr a0, 0x300
    CHECK a0, 6144
    csrr a0, 0x301
#ifdef RVC_DISABLED
    CHECK a0, 1073746176
#else
    CHECK a0, 1073746180
#endif
    csrr a0, 0x304
    CHECK a0, 0
    csrr a0, 0x305
    CHECK a0, 0
    csrr a0, 0x320
    CHECK a0, 0
    csrr a0, 0x340
    CHECK a0, 0
    csrr a0, 0x341
    CHECK a0, 0
    csrr a0, 0x342
    CHECK a0, 0
    csrr a0, 0x343
    CHECK a0, 0
    csrr a0, 0x344
    CHECK a0, 0
    csrr a0, 0xf11
    CHECK a0, 0
    csrr a0, 0xf12
    CHECK a0, 0
    csrr a0, 0xf13
    CHECK a0, 0
    csrr a0, 0xf14
    CHECK a0, 0
    csrr a0, 0x323
    CHECK a0, 0
    csrr a0, 0xb03
    CHECK a0, 0
    csrr a0, 0xb83
    CHECK a0, 0
    csrr a0, 0x324
    CHECK a0, 0
    csrr a0, 0xb04
    CHECK a0, 0
    csrr a0, 0xb84
    CHECK a0, 0
    csrr a0, 0x325
    CHECK a0, 0
    csrr a0, 0xb05
    CHECK a0, 0
    csrr a0, 0xb85
    CHECK a0, 0
    csrr a0, 0x326
    CHECK a0, 0
    csrr a0, 0xb06
    CHECK a0, 0
    csrr a0, 0xb86
    CHECK a0, 0
    csrr a0, 0x327
    CHECK a0, 0
    csrr a0, 0xb07
    CHECK a0, 0
    csrr a0, 0xb87
    CHECK a0, 0
    csrr a0, 0x328
    CHECK a0, 0
    csrr a0, 0xb08
    CHECK a0, 0
    csrr a0, 0xb88
    CHECK a0, 0
    csrr a0, 0x329
    CHECK a0, 0
    csrr a0, 0xb09
    CHECK a0, 0
    csrr a0, 0xb89
    CHECK a0, 0
    csrr a0, 0x32a
    CHECK a0, 0
    csrr a0, 0xb0a
    CHECK a0, 0
    csrr a0, 0xb8a
    CHECK a0, 0
    csrr a0, 0xb80
    CHECK a0, 0
    csrr a0, 0xb82
    CHECK a0, 0
#endif
    la t0, unexpected_trap
    csrw mtvec, t0
    csrw mie, zero
    csrw mstatus, zero
#ifndef SPIKE_SMOKE
    li t0, 0x7fd
    csrw mcountinhibit, t0
    li a0, 4294967295
    csrw mstatus, a0
    csrr a1, mstatus
    CHECK a1, 6280
    li a0, 4294967295
    csrw mie, a0
    csrr a1, mie
    CHECK a1, 2184
    li a0, 2309737967
    csrw mscratch, a0
    csrr a1, mscratch
    CHECK a1, 2309737967
    li a0, 2147483651
    csrw mepc, a0
    csrr a1, mepc
#ifdef RVC_DISABLED
    CHECK a1, 2147483648
#else
    CHECK a1, 2147483650
#endif
    li a0, 2147483659
    csrw mcause, a0
    csrr a1, mcause
    CHECK a1, 2147483659
    li a0, 305419896
    csrw mtval, a0
    csrr a1, mtval
    CHECK a1, 305419896
    li a0, 4294967295
    csrw mcountinhibit, a0
    csrr a1, mcountinhibit
    CHECK a1, 2045
    csrw mie, zero
    csrw mstatus, zero
    csrr a0, misa
    csrw misa, zero
    csrr a1, misa
    bne a0, a1, fail
    la a0, expected_trap
    ori a0, a0, 2
    csrw mtvec, a0
    csrr a1, mtvec
    andi a1, a1, 3
    CHECK a1, 0
    la a0, expected_trap
    ori a0, a0, 3
    csrw mtvec, a0
    csrr a1, mtvec
    andi a1, a1, 3
    CHECK a1, 0
    li a0, -1
    csrw 0x323, a0
    csrr a1, 0x323
    CHECK a1, 31
    li a0, -1
    csrw 0x324, a0
    csrr a1, 0x324
    CHECK a1, 31
    li a0, -1
    csrw 0x325, a0
    csrr a1, 0x325
    CHECK a1, 31
    li a0, -1
    csrw 0x326, a0
    csrr a1, 0x326
    CHECK a1, 31
    li a0, -1
    csrw 0x327, a0
    csrr a1, 0x327
    CHECK a1, 31
    li a0, -1
    csrw 0x328, a0
    csrr a1, 0x328
    CHECK a1, 31
    li a0, -1
    csrw 0x329, a0
    csrr a1, 0x329
    CHECK a1, 31
    li a0, -1
    csrw 0x32a, a0
    csrr a1, 0x32a
    CHECK a1, 31
    li a0, 0x13579bdf
    csrw 0xb00, a0
    csrr a1, 0xb00
    bne a1, a0, fail
    csrr a1, 0xc00
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb80, a0
    csrr a1, 0xb80
    bne a1, a0, fail
    csrr a1, 0xc80
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb02, a0
    csrr a1, 0xb02
    bne a1, a0, fail
    csrr a1, 0xc02
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb82, a0
    csrr a1, 0xb82
    bne a1, a0, fail
    csrr a1, 0xc82
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb03, a0
    csrr a1, 0xb03
    bne a1, a0, fail
    csrr a1, 0xc03
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb83, a0
    csrr a1, 0xb83
    bne a1, a0, fail
    csrr a1, 0xc83
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb04, a0
    csrr a1, 0xb04
    bne a1, a0, fail
    csrr a1, 0xc04
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb84, a0
    csrr a1, 0xb84
    bne a1, a0, fail
    csrr a1, 0xc84
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb05, a0
    csrr a1, 0xb05
    bne a1, a0, fail
    csrr a1, 0xc05
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb85, a0
    csrr a1, 0xb85
    bne a1, a0, fail
    csrr a1, 0xc85
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb06, a0
    csrr a1, 0xb06
    bne a1, a0, fail
    csrr a1, 0xc06
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb86, a0
    csrr a1, 0xb86
    bne a1, a0, fail
    csrr a1, 0xc86
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb07, a0
    csrr a1, 0xb07
    bne a1, a0, fail
    csrr a1, 0xc07
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb87, a0
    csrr a1, 0xb87
    bne a1, a0, fail
    csrr a1, 0xc87
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb08, a0
    csrr a1, 0xb08
    bne a1, a0, fail
    csrr a1, 0xc08
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb88, a0
    csrr a1, 0xb88
    bne a1, a0, fail
    csrr a1, 0xc88
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb09, a0
    csrr a1, 0xb09
    bne a1, a0, fail
    csrr a1, 0xc09
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb89, a0
    csrr a1, 0xb89
    bne a1, a0, fail
    csrr a1, 0xc89
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb0a, a0
    csrr a1, 0xb0a
    bne a1, a0, fail
    csrr a1, 0xc0a
    bne a1, a0, fail
    li a0, 0x13579bdf
    csrw 0xb8a, a0
    csrr a1, 0xb8a
    bne a1, a0, fail
    csrr a1, 0xc8a
    bne a1, a0, fail
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_0
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_0, csr_resume_0
csr_fault_0:
    csrw 0xc00, zero
csr_resume_0:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_1
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_1, csr_resume_1
csr_fault_1:
    csrw 0xc01, zero
csr_resume_1:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_2
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_2, csr_resume_2
csr_fault_2:
    csrw 0xc02, zero
csr_resume_2:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_3
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_3, csr_resume_3
csr_fault_3:
    csrw 0xc03, zero
csr_resume_3:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_4
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_4, csr_resume_4
csr_fault_4:
    csrw 0xc04, zero
csr_resume_4:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_5
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_5, csr_resume_5
csr_fault_5:
    csrw 0xc05, zero
csr_resume_5:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_6
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_6, csr_resume_6
csr_fault_6:
    csrw 0xc06, zero
csr_resume_6:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_7
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_7, csr_resume_7
csr_fault_7:
    csrw 0xc07, zero
csr_resume_7:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_8
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_8, csr_resume_8
csr_fault_8:
    csrw 0xc08, zero
csr_resume_8:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_9
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_9, csr_resume_9
csr_fault_9:
    csrw 0xc09, zero
csr_resume_9:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_10
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_10, csr_resume_10
csr_fault_10:
    csrw 0xc0a, zero
csr_resume_10:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_11
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_11, csr_resume_11
csr_fault_11:
    csrw 0xc80, zero
csr_resume_11:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_12
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_12, csr_resume_12
csr_fault_12:
    csrw 0xc81, zero
csr_resume_12:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_13
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_13, csr_resume_13
csr_fault_13:
    csrw 0xc82, zero
csr_resume_13:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_14
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_14, csr_resume_14
csr_fault_14:
    csrw 0xc83, zero
csr_resume_14:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_15
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_15, csr_resume_15
csr_fault_15:
    csrw 0xc84, zero
csr_resume_15:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_16
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_16, csr_resume_16
csr_fault_16:
    csrw 0xc85, zero
csr_resume_16:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_17
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_17, csr_resume_17
csr_fault_17:
    csrw 0xc86, zero
csr_resume_17:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_18
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_18, csr_resume_18
csr_fault_18:
    csrw 0xc87, zero
csr_resume_18:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_19
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_19, csr_resume_19
csr_fault_19:
    csrw 0xc88, zero
csr_resume_19:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_20
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_20, csr_resume_20
csr_fault_20:
    csrw 0xc89, zero
csr_resume_20:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_21
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_21, csr_resume_21
csr_fault_21:
    csrw 0xc8a, zero
csr_resume_21:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_22
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_22, csr_resume_22
csr_fault_22:
    csrw 0xf11, zero
csr_resume_22:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_23
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_23, csr_resume_23
csr_fault_23:
    csrw 0xf12, zero
csr_resume_23:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_24
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_24, csr_resume_24
csr_fault_24:
    csrw 0xf13, zero
csr_resume_24:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_25
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_25, csr_resume_25
csr_fault_25:
    csrw 0xf14, zero
csr_resume_25:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_26
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_26, csr_resume_26
csr_fault_26:
    csrw 0x344, zero
csr_resume_26:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_27
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_27, csr_resume_27
csr_fault_27:
    csrw 0x7ff, zero
csr_resume_27:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_28
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_28, csr_resume_28
csr_fault_28:
    csrw 0x7a0, zero
csr_resume_28:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_29
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_29, csr_resume_29
csr_fault_29:
    csrw 0x7a1, zero
csr_resume_29:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_30
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_30, csr_resume_30
csr_fault_30:
    csrw 0x7a2, zero
csr_resume_30:
#endif
#ifndef SPIKE_SMOKE
    la a0, csr_fault_31
    lw t2, 0(a0)
    EXPECT 2, t2, csr_fault_31, csr_resume_31
csr_fault_31:
    csrw 0x7a3, zero
csr_resume_31:
#endif
    li a0, 0x55
    csrrw a1, mscratch, a0
    csrr a1, mscratch
    CHECK a1, 0x55
    li a0, 0x0a
    csrrs a1, mscratch, a0
    CHECK a1, 0x55
    csrr a1, mscratch
    CHECK a1, 0x5f
    li a0, 3
    csrrc a1, mscratch, a0
    CHECK a1, 0x5f
    csrr a1, mscratch
    CHECK a1, 0x5c
    csrrwi a1, mscratch, 1
    CHECK a1, 0x5c
    csrrsi a1, mscratch, 2
    CHECK a1, 1
    csrrci a1, mscratch, 1
    CHECK a1, 3
    csrr a1, mscratch
    CHECK a1, 2
    FINISH
