/* File: p-06/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: CSR 等老指令排空且单独发射。
 * Clock: clk_sys. */
#include "test.h"
    START
    la a0, scratch
    li a1, 23
    sw a1, 0(a0)
    mul a2, a1, a1
csr_serial:
    csrrw a3, mscratch, a2
    addi a4, a3, 1
    csrr a5, mscratch
    CHECK a4, 1
    CHECK a5, 529
    FINISH
