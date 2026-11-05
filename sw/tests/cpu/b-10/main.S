/* File: b-10/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan B-10.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a0, 0
    sw zero, 0(a4)
    fence
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
flush_load_branch:
    beq zero, zero, flush_load_target
    addi a0, a0, 99
wrong_load:
    lw a1, 0(a4)
    addi a0, a0, 77
flush_load_target:
    CHECK a0, 0
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
flush_store_branch:
    beq zero, zero, flush_store_target
    addi a0, a0, 99
wrong_store:
    sw a1, 0(a4)
    addi a0, a0, 77
flush_store_target:
    CHECK a0, 0
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
flush_branch_branch:
    beq zero, zero, flush_branch_target
    addi a0, a0, 99
wrong_branch:
    beq zero, zero, fail
    addi a0, a0, 77
flush_branch_target:
    CHECK a0, 0
probe_branch:
    bne a0, zero, fail
    lw a1, 0(a4)
    CHECK a1, 0
    FINISH
