/* File: l-01/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan L-01.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a0, 7
    sw a0, 0(a4)
    fence
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_beq_rs1_load:
    lw a3, 0(a1)
lcb_beq_rs1_branch:
    beq a3, a0, lcb_beq_rs1_taken
    j fail
lcb_beq_rs1_taken:
    nop
lcb_beq_rs1_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_beq_rs2_load:
    lw a3, 0(a1)
lcb_beq_rs2_branch:
    beq a0, a3, lcb_beq_rs2_taken
    j fail
lcb_beq_rs2_taken:
    nop
lcb_beq_rs2_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_beq_both_load:
    lw a3, 0(a1)
lcb_beq_both_branch:
    beq a3, a3, lcb_beq_both_taken
    j fail
lcb_beq_both_taken:
    nop
lcb_beq_both_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bne_rs1_load:
    lw a3, 0(a1)
lcb_bne_rs1_branch:
    bne a3, a0, lcb_bne_rs1_taken
    j lcb_bne_rs1_done
lcb_bne_rs1_taken:
    j fail
lcb_bne_rs1_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bne_rs2_load:
    lw a3, 0(a1)
lcb_bne_rs2_branch:
    bne a0, a3, lcb_bne_rs2_taken
    j lcb_bne_rs2_done
lcb_bne_rs2_taken:
    j fail
lcb_bne_rs2_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bne_both_load:
    lw a3, 0(a1)
lcb_bne_both_branch:
    bne a3, a3, lcb_bne_both_taken
    j lcb_bne_both_done
lcb_bne_both_taken:
    j fail
lcb_bne_both_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_blt_rs1_load:
    lw a3, 0(a1)
lcb_blt_rs1_branch:
    blt a3, a0, lcb_blt_rs1_taken
    j lcb_blt_rs1_done
lcb_blt_rs1_taken:
    j fail
lcb_blt_rs1_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_blt_rs2_load:
    lw a3, 0(a1)
lcb_blt_rs2_branch:
    blt a0, a3, lcb_blt_rs2_taken
    j lcb_blt_rs2_done
lcb_blt_rs2_taken:
    j fail
lcb_blt_rs2_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_blt_both_load:
    lw a3, 0(a1)
lcb_blt_both_branch:
    blt a3, a3, lcb_blt_both_taken
    j lcb_blt_both_done
lcb_blt_both_taken:
    j fail
lcb_blt_both_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bge_rs1_load:
    lw a3, 0(a1)
lcb_bge_rs1_branch:
    bge a3, a0, lcb_bge_rs1_taken
    j fail
lcb_bge_rs1_taken:
    nop
lcb_bge_rs1_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bge_rs2_load:
    lw a3, 0(a1)
lcb_bge_rs2_branch:
    bge a0, a3, lcb_bge_rs2_taken
    j fail
lcb_bge_rs2_taken:
    nop
lcb_bge_rs2_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bge_both_load:
    lw a3, 0(a1)
lcb_bge_both_branch:
    bge a3, a3, lcb_bge_both_taken
    j fail
lcb_bge_both_taken:
    nop
lcb_bge_both_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bltu_rs1_load:
    lw a3, 0(a1)
lcb_bltu_rs1_branch:
    bltu a3, a0, lcb_bltu_rs1_taken
    j lcb_bltu_rs1_done
lcb_bltu_rs1_taken:
    j fail
lcb_bltu_rs1_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bltu_rs2_load:
    lw a3, 0(a1)
lcb_bltu_rs2_branch:
    bltu a0, a3, lcb_bltu_rs2_taken
    j lcb_bltu_rs2_done
lcb_bltu_rs2_taken:
    j fail
lcb_bltu_rs2_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bltu_both_load:
    lw a3, 0(a1)
lcb_bltu_both_branch:
    bltu a3, a3, lcb_bltu_both_taken
    j lcb_bltu_both_done
lcb_bltu_both_taken:
    j fail
lcb_bltu_both_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bgeu_rs1_load:
    lw a3, 0(a1)
lcb_bgeu_rs1_branch:
    bgeu a3, a0, lcb_bgeu_rs1_taken
    j fail
lcb_bgeu_rs1_taken:
    nop
lcb_bgeu_rs1_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bgeu_rs2_load:
    lw a3, 0(a1)
lcb_bgeu_rs2_branch:
    bgeu a0, a3, lcb_bgeu_rs2_taken
    j fail
lcb_bgeu_rs2_taken:
    nop
lcb_bgeu_rs2_done:
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
lcb_bgeu_both_load:
    lw a3, 0(a1)
lcb_bgeu_both_branch:
    bgeu a3, a3, lcb_bgeu_both_taken
    j fail
lcb_bgeu_both_taken:
    nop
lcb_bgeu_both_done:
    /* The first compare is not taken; the following JAL waits while it is in E. */
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a1, a4, 0
limit_load:
    lw a3, 0(a1)
limit_branch:
    bne a3, a0, fail
limit_jal:
    jal zero, limit_done
    j fail
limit_done:
    FINISH
