/* File: b-07/main.S; Spec: cpu-spec 4.2-4.5; cpu-testplan B-07.
 * Description: Check ordered slots across pipeline assignment.
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    la a4, scratch
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
direction_older:
    addi a0, a0, 1
direction_slot1:
    beq zero, zero, direction_target
    addi a0, a0, 100
direction_target:
    CHECK a0, 1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
flush_branch:
    beq zero, zero, flush_target
flush_load:
    lw a1, 0(a4)
flush_target:
    CHECK a0, 1
    li a3, 32
    j training_entry
    .balign 8
training_entry:
    addi a0, zero, 19
trained_branch:
    beq zero, zero, target_a
    j fail
target_a:
    addi a3, a3, -1
    bnez a3, training_entry
    la t0, new_encoding
    lw t1, 0(t0)
    la t0, trained_branch
    sw t1, 0(t0)
    fence.i
    /* Restore the all-taken twelve-bit GHR used during training. */
    .rept 12
    beq zero, zero, 1f
1:
    .endr
    j training_entry
target_b:
    CHECK a0, 19
    j finished
    .balign 4
new_encoding:
    .set delta, target_b-trained_branch
    .set imm_hi, (((delta >> 12) & 1) << 31) | (((delta >> 5) & 63) << 25)
    .set imm_lo, (((delta >> 1) & 15) << 8) | (((delta >> 11) & 1) << 7)
    .word 0x63 | imm_hi | imm_lo
finished:
    FINISH
