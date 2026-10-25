/* ========================================================================== */
/* File        : csr_pipeline.S                                               */
/* Author      : Edward ZC                                                    */
/* Description : Directed CSR sub-pipeline ordering and forwarding test.      */
/* Notes       : Covers stable M1/M2 forwarding, CSR serialization, dynamic   */
/*               counter WB availability and optional FCSR late sampling.     */
/* ========================================================================== */

.equ TOHOST, 0x80001000

.section .text
.globl _start
.option norvc
_start:
    /* Stable CSR, immediate M1-forwarded consumer. */
    li      t0, 0x12345678
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t1, t0, fail

    /* Stable CSR, one-gap M2-forwarded consumer. */
    csrr    t1, mscratch
    addi    a0, zero, 1
    bne     t1, t0, fail

    /* Stable CSR, two-gap WB/register-file consumer. */
    csrr    t1, mscratch
    addi    a0, a0, 1
    addi    a0, a0, 1
    bne     t1, t0, fail

    /* CSR-to-CSR ordering and pre-write rd value. */
    li      t2, 0x55aa00ff
    csrrw   t3, mscratch, t2
    bne     t3, t0, fail
    csrr    t4, mscratch
    bne     t4, t2, fail

    /* CSRRS RMW ordering. */
    li      t5, 0x00000f00
    csrrs   t3, mscratch, t5
    bne     t3, t2, fail
    or      t2, t2, t5
    csrr    t4, mscratch
    bne     t4, t2, fail

    /* Dynamic CSR data is sampled at commit and released from WB. A write to
       minstret suppresses retirement increment for the writing instruction. */
    li      t2, 100
    csrw    minstret, t2
    csrr    t3, minstret
    bne     t3, t2, fail

    csrr    t3, mcycle
    beqz    t3, fail

#ifdef EDRV32_TEST_FLOAT
    /* Enable FS, then verify FCSR write/read and immediate integer consumer. */
    li      t0, (1 << 13)
    csrs    mstatus, t0
    li      t0, 0x21
    csrw    fcsr, t0
    csrr    t1, fcsr
    andi    t1, t1, 0xff
    bne     t1, t0, fail
#endif

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

