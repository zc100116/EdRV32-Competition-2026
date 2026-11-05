/* File: p-04/main.S; Spec: cpu-spec 4.4, 4.10; cpu-testplan P-04.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a1, 13
    sw a1, 0(a4)
    fence
    li a2, 7
    csrw mscratch, a1
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a0, a4, 0
latency_load_0_producer:
    lw a3, 0(a0)
latency_load_0_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a0, a4, 0
latency_load_1_producer:
    lw a3, 0(a0)
    addi a6, a6, 1
latency_load_1_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a0, a4, 0
latency_load_2_producer:
    lw a3, 0(a0)
    addi a6, a6, 1
    addi a6, a6, 1
latency_load_2_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a0, a4, 0
latency_load_3_producer:
    lw a3, 0(a0)
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_load_3_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
    addi a0, a4, 0
latency_load_4_producer:
    lw a3, 0(a0)
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_load_4_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_early_0_producer:
    lw a3, 0(a4)
latency_early_0_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_early_1_producer:
    lw a3, 0(a4)
    addi a6, a6, 1
latency_early_1_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_early_2_producer:
    lw a3, 0(a4)
    addi a6, a6, 1
    addi a6, a6, 1
latency_early_2_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_early_3_producer:
    lw a3, 0(a4)
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_early_3_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_early_4_producer:
    lw a3, 0(a4)
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_early_4_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_mul_0_producer:
    mul a3, a1, a2
latency_mul_0_consumer:
    addi a5, a3, 1
    CHECK a5, 92
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_mul_1_producer:
    mul a3, a1, a2
    addi a6, a6, 1
latency_mul_1_consumer:
    addi a5, a3, 1
    CHECK a5, 92
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_mul_2_producer:
    mul a3, a1, a2
    addi a6, a6, 1
    addi a6, a6, 1
latency_mul_2_consumer:
    addi a5, a3, 1
    CHECK a5, 92
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_mul_3_producer:
    mul a3, a1, a2
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_mul_3_consumer:
    addi a5, a3, 1
    CHECK a5, 92
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_mul_4_producer:
    mul a3, a1, a2
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_mul_4_consumer:
    addi a5, a3, 1
    CHECK a5, 92
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_csr_0_producer:
    csrr a3, mscratch
latency_csr_0_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_csr_1_producer:
    csrr a3, mscratch
    addi a6, a6, 1
latency_csr_1_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_csr_2_producer:
    csrr a3, mscratch
    addi a6, a6, 1
    addi a6, a6, 1
latency_csr_2_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_csr_3_producer:
    csrr a3, mscratch
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_csr_3_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    .balign 8
    csrr zero, mscratch
    csrr zero, mscratch
latency_csr_4_producer:
    csrr a3, mscratch
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
    addi a6, a6, 1
latency_csr_4_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    FINISH
