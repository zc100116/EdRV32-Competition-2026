/* File: b-02/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 反复变化的 JALR 目标和故意不同于 RAS 的返回地址。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    li a1, 8
    la a2, target_a
jalr_loop:
jalr_target:
    jalr ra, 0(a2)
    addi a1, a1, -1
    beqz a1, jalr_done
    la a2, target_b
    andi t0, a1, 1
    bnez t0, jalr_loop
    la a2, target_a
    j jalr_loop
target_a:
    addi a0, a0, 1
    ret
target_b:
    addi a0, a0, 2
    ret
jalr_done:
    CHECK a0, 12
    jal ra, ras_wrong
ras_actual_return:
    j ras_done
    j ras_done
ras_wrong:
    la ra, ras_actual_return
    addi ra, ra, 4
ras_wrong_return:
    ret
ras_done:
    addi a0, a0, 1
    CHECK a0, 13
    FINISH
