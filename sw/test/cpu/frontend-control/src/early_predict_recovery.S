// ============================================================================
// File        : early_predict_recovery.S
// Author      : Edward ZC
// Description : Stale-BTB architectural recovery test for IF2 early steering.
// Notes       : Trains taken branches at slot0 and cross-word slot1, replaces
//               them with ordinary ADDI instructions, executes FENCE.I, then
//               verifies EX redirects from the stale target to sequential PC.
// ============================================================================

    .equ TOHOST, 0x80001000

    .section .text
    .globl _start
    .option rvc
_start:
    li      s2, 0
    li      t0, 4

    // A slot0 branch becomes a non-control-flow instruction at the same PC.
    .balign 4
    .globl stale_slot0_site
stale_slot0_site:
    .option push
    .option norvc
    beq     zero, zero, stale_slot0_target
    .option pop
stale_slot0_sequential:
    li      t1, 1
    bne     s2, t1, fail
    j       setup_slot1

stale_slot0_target:
    addi    t0, t0, -1
    bnez    t0, stale_slot0_site
    la      t1, stale_slot0_site
    li      t2, 0x00190913       // addi s2, s2, 1
    sw      t2, 0(t1)
    fence   rw, rw
    fence.i
    j       stale_slot0_site

setup_slot1:
    li      s3, 0
    li      t0, 4

    // The same stale-BTB replay with a 32-bit branch beginning at PC[1]=1.
    .balign 4
    c.nop
    .globl stale_slot1_site
stale_slot1_site:
    .option push
    .option norvc
    beq     zero, zero, stale_slot1_target
    .option pop
stale_slot1_sequential:
    li      t1, 1
    bne     s3, t1, fail
    j       pass

stale_slot1_target:
    addi    t0, t0, -1
    bnez    t0, stale_slot1_site
    la      t1, stale_slot1_site
    li      t2, 0x8993           // low half of addi s3, s3, 1
    sh      t2, 0(t1)
    li      t2, 0x0019           // high half
    sh      t2, 2(t1)
    fence   rw, rw
    fence.i
    j       stale_slot1_site

pass:
    li      t0, 1
    li      t1, TOHOST
    sw      t0, 0(t1)
1:
    j       1b

fail:
    li      t0, 3
    li      t1, TOHOST
    sw      t0, 0(t1)
2:
    j       2b
