/* File: p-08/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 连续 store 与字节、半字重叠 load/符号扩展。
 * Clock: clk_sys. */
#include "test.h"
    START
    la a0, scratch
    li a1, 0x12345678
    li a2, 0xaabbccdd
    .balign 8
stores_begin:
    sw a1, 0(a0)
    sw a2, 4(a0)
    sw a1, 8(a0)
    sw a2, 12(a0)
    lw a3, 12(a0)
    CHECK a3, 0xaabbccdd
    li a4, 0xee
    sb a4, 1(a0)
    lw a3, 0(a0)
    CHECK a3, 0x1234ee78
    li a4, 0x89ab
    sh a4, 2(a0)
    lw a3, 0(a0)
    CHECK a3, 0x89abee78
    lb a3, 1(a0)
    CHECK a3, -18
    lbu a3, 1(a0)
    CHECK a3, 238
    lh a3, 2(a0)
    CHECK a3, 0xffff89ab
    lhu a3, 2(a0)
    CHECK a3, 0x89ab
    FINISH
