/* File: p-03/main.S; Spec: cpu-testplan P-03, cpu-spec 4.3.
 * Description: Exercise each real bypass source and consumer operand/slot.
 * Clock: clk_sys. */
#include "test.h"
    START
    li a4, 0
    li a5, 0
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_E_0_1_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
bypass_E_0_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_E_0_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a3, zero, 42
bypass_E_0_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_E_0_2_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
bypass_E_0_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_E_0_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a3, zero, 42
bypass_E_0_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_E_1_1_0_producer:
    addi a2, a0, 7
bypass_E_1_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_E_1_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 42
bypass_E_1_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_E_1_2_0_producer:
    addi a2, a0, 7
bypass_E_1_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_E_1_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 42
bypass_E_1_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_M_0_1_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_0_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_M_0_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_M_0_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_M_0_2_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_0_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_M_0_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_M_0_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_M_1_1_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_1_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_M_1_1_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_M_1_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_M_1_2_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_1_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_M_1_2_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_M_1_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_W_0_1_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_0_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_W_0_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_W_0_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_W_0_2_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_0_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
bypass_W_0_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_W_0_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_W_1_1_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_1_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_W_1_1_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_W_1_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_W_1_2_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_1_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
    csrw mscratch, zero
    addi a3, zero, 41
bypass_W_1_2_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a5, a5, 1
    addi a4, a4, 1
    addi a5, a5, 1
    addi a3, zero, 42
bypass_W_1_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    /* v0.15 reachable swapped-group sources. Pipe0 cannot produce an E-stage
     * ALU value in a swapped group: it is load/store/mul/div/JALR only.
     * E0 uses JALR's link; M0 uses load and W0 uses multiply. The existing
     * 24 ALU cases cover every source/operand/consumer-slot combination.
     */
    la a4, scratch
    li a0, 13
    li a1, 2
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
swap_alu_rs1_producer:
    addi a2, zero, 26
    lw a3, 0(a4)
swap_alu_rs1_entry:
swap_alu_rs1_consumer:
    add a6, a2, zero
    lw a3, 0(a4)
    CHECK a6, 26
    la a4, scratch
    li a0, 13
    li a1, 2
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
swap_alu_rs2_producer:
    addi a2, zero, 26
    lw a3, 0(a4)
swap_alu_rs2_entry:
    addi a3, zero, 42
swap_alu_rs2_consumer:
    mul a6, a1, a2
    CHECK a6, 52
    la a4, scratch
    li a0, 13
    li a1, 2
    la a5, swap_jalr_rs1_entry
    li t6, 0
    .balign 8
.Lswap_jalr_rs1_warm:
    csrr zero, mscratch
    csrr zero, mscratch
    addi a3, zero, 41
swap_jalr_rs1_producer:
    jalr a2, 0(a5)
swap_jalr_rs1_entry:
swap_jalr_rs1_consumer:
    add a6, a2, zero
    lw a3, 0(a4)
    # A cold JALR redirects; measure E0 bypass on the second, predicted visit.
    addi t6, t6, 1
    li t5, 2
    blt t6, t5, .Lswap_jalr_rs1_warm
    la t5, swap_jalr_rs1_entry
    bne a6, t5, fail
    la a4, scratch
    li a0, 13
    li a1, 2
    la a5, swap_jalr_rs2_entry
    li t6, 0
    .balign 8
.Lswap_jalr_rs2_warm:
    csrr zero, mscratch
    csrr zero, mscratch
    addi a3, zero, 41
swap_jalr_rs2_producer:
    jalr a2, 0(a5)
swap_jalr_rs2_entry:
    addi a3, zero, 42
swap_jalr_rs2_consumer:
    mul a6, a1, a2
    addi t6, t6, 1
    li t5, 2
    blt t6, t5, .Lswap_jalr_rs2_warm
    la t5, swap_jalr_rs2_entry
    slli t5, t5, 1
    bne a6, t5, fail
    la a4, scratch
    li a0, 13
    li a1, 2
    li t0, 26
    sw t0, 0(a4)
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a4, a4, 0
    nop
    addi a3, zero, 41
swap_load_rs1_producer:
    lw a2, 0(a4)
swap_load_rs1_entry:
swap_load_rs1_consumer:
    add a6, a2, zero
    lw a3, 0(a4)
    CHECK a6, 26
    la a4, scratch
    li a0, 13
    li a1, 2
    li t0, 26
    sw t0, 0(a4)
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a4, a4, 0
    nop
    addi a3, zero, 41
swap_load_rs2_producer:
    lw a2, 0(a4)
swap_load_rs2_entry:
    # Hold both consumers until the producer result reaches its specified bypass stage.
    addi a3, a2, 42
swap_load_rs2_consumer:
    mul a6, a1, a2
    CHECK a6, 52
    la a4, scratch
    li a0, 13
    li a1, 2
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a3, zero, 41
swap_mul_rs1_producer:
    mul a2, a0, a1
swap_mul_rs1_entry:
swap_mul_rs1_consumer:
    add a6, a2, zero
    lw a3, 0(a4)
    CHECK a6, 26
    la a4, scratch
    li a0, 13
    li a1, 2
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a3, zero, 41
swap_mul_rs2_producer:
    mul a2, a0, a1
swap_mul_rs2_entry:
    # Hold both consumers until the producer result reaches its specified bypass stage.
    addi a3, a2, 42
swap_mul_rs2_consumer:
    mul a6, a1, a2
    CHECK a6, 52
    la a4, scratch
    li t0, 26
    sw t0, 0(a4)
    fence
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
early_load_producer:
    lw a2, 0(a4)
    addi a3, zero, 41
early_load_consumer:
    add a6, a2, zero
    lw a3, 4(a4)
    CHECK a6, 26
    FINISH
