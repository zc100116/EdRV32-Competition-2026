/* File: p-04/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: load、乘法、CSR 后隔 0–3 条的相关消费者。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a4, 0
    la a0, scratch
    li a1, 13
    sw a1, 0(a0)
    li a2, 7
    csrw mscratch, a1
.balign 8
latency_load_0_producer:
    lw a3, 0(a0)
latency_load_0_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_load_1_producer:
    lw a3, 0(a0)
    addi a4, a4, 1
latency_load_1_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_load_2_producer:
    lw a3, 0(a0)
    addi a4, a4, 1
    addi a4, a4, 1
latency_load_2_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_load_3_producer:
    lw a3, 0(a0)
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
latency_load_3_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_mul_0_producer:
    mul a3, a1, a2
latency_mul_0_consumer:
    addi a5, a3, 1
    CHECK a5, 92
.balign 8
latency_mul_1_producer:
    mul a3, a1, a2
    addi a4, a4, 1
latency_mul_1_consumer:
    addi a5, a3, 1
    CHECK a5, 92
.balign 8
latency_mul_2_producer:
    mul a3, a1, a2
    addi a4, a4, 1
    addi a4, a4, 1
latency_mul_2_consumer:
    addi a5, a3, 1
    CHECK a5, 92
.balign 8
latency_mul_3_producer:
    mul a3, a1, a2
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
latency_mul_3_consumer:
    addi a5, a3, 1
    CHECK a5, 92
.balign 8
latency_csr_0_producer:
    csrr a3, mscratch
latency_csr_0_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_csr_1_producer:
    csrr a3, mscratch
    addi a4, a4, 1
latency_csr_1_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_csr_2_producer:
    csrr a3, mscratch
    addi a4, a4, 1
    addi a4, a4, 1
latency_csr_2_consumer:
    addi a5, a3, 1
    CHECK a5, 14
.balign 8
latency_csr_3_producer:
    csrr a3, mscratch
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
latency_csr_3_consumer:
    addi a5, a3, 1
    CHECK a5, 14
    FINISH
