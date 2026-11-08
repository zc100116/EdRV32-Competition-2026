/* File: a-01/main.S; Spec: cpu-spec 4.4, 4.10; cpu-testplan A-01.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    sw a4, 0(a4)
    fence
    csrw mscratch, a4
    li a2, 1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_same_slot:
    addi a0, a4, 0
load_same_slot:
    lw a3, 0(a0)
use_same_slot:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_e_alu:
    addi a0, a4, 0
    addi a7, zero, 1
load_e_alu:
    lw a3, 0(a0)
use_e_alu:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_m_alu:
    addi a0, a4, 0
    addi a7, zero, 1
    addi a6, zero, 2
    addi a7, zero, 3
load_m_alu:
    lw a3, 0(a0)
use_m_alu:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_m_load:
    lw a0, 0(a4)
    addi a7, zero, 1
    addi a6, zero, 2
    addi a7, zero, 3
load_m_load:
    lw a3, 0(a0)
use_m_load:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_m_csr:
    csrr a0, mscratch
    addi a7, zero, 1
    addi a6, zero, 2
    addi a7, zero, 3
load_m_csr:
    lw a3, 0(a0)
use_m_csr:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_multiply:
    mul a0, a4, a2
    addi a7, zero, 1
load_multiply:
    lw a3, 0(a0)
use_multiply:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_w:
    addi a0, a4, 0
    addi a7, zero, 1
    addi a6, zero, 2
    addi a7, zero, 3
    addi a6, zero, 2
    addi a7, zero, 3
load_w:
    lw a3, 0(a0)
use_w:
    addi a5, a3, 0
    bne a5, a4, fail
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
address_x0:
    addi a0, a4, 0
    addi a7, zero, 1
    addi a6, zero, 2
    addi a7, zero, 3
    addi a6, zero, 2
    addi a7, zero, 3
    addi a6, zero, 2
    addi a7, zero, 3
load_x0:
    lw a3, 0(zero)
use_x0:
    addi a5, a3, 0
    FINISH
