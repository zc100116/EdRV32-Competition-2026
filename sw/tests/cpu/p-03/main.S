/* File: p-03/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 24 个 E/M/W × 两条管线 × rs1/rs2 × 两个消费者槽位旁路场景。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a4, 0
    li a5, 0
    li a0, 19
    li a1, 23
.balign 8
bypass_E_0_1_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
bypass_E_0_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
bypass_E_0_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a5, a5, 1
bypass_E_0_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
bypass_E_0_2_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
bypass_E_0_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
bypass_E_0_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a5, a5, 1
bypass_E_0_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_E_1_1_0_producer:
    addi a2, a0, 7
bypass_E_1_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_E_1_1_1_producer:
    addi a2, a0, 7
    addi a5, a5, 1
bypass_E_1_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_E_1_2_0_producer:
    addi a2, a0, 7
bypass_E_1_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_E_1_2_1_producer:
    addi a2, a0, 7
    addi a5, a5, 1
bypass_E_1_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
bypass_M_0_1_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
bypass_M_0_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
bypass_M_0_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_0_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
bypass_M_0_2_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
bypass_M_0_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
bypass_M_0_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_0_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_M_1_1_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
bypass_M_1_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_M_1_1_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_1_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_M_1_2_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
bypass_M_1_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_M_1_2_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_M_1_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
bypass_W_0_1_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
bypass_W_0_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
bypass_W_0_1_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_0_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
bypass_W_0_2_0_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
bypass_W_0_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
bypass_W_0_2_1_producer:
    addi a2, a0, 7
    addi a3, zero, 41
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_0_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_W_1_1_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
bypass_W_1_1_0_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_W_1_1_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_1_1_1_consumer:
    sub a6, a2, a1
    CHECK a6, 3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_W_1_2_0_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
bypass_W_1_2_0_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    li a0, 19
    li a1, 23
.balign 8
    addi a3, zero, 41
bypass_W_1_2_1_producer:
    addi a2, a0, 7
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a4, a4, 1
    addi a5, a5, 1
bypass_W_1_2_1_consumer:
    sub a6, a1, a2
    CHECK a6, -3
    FINISH
