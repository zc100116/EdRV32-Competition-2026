/* File: a-04/main.S; Spec: cpu-spec 4.4, 4.10-4.11; cpu-testplan A-04.
 * Description: Directed architectural and timing obligations for v0.17.
 * Clock: clk_sys. */
#include "test.h"
    START
    la a4, scratch
    li a1, 0x11223344
    li a2, 0x55
    li a3, 0x6677
    fence
stores_begin:
    sw a1, 0(a4)
    sb a2, 1(a4)
    sh a3, 2(a4)
    sw a1, 4(a4)
forward_load:
    lw a0, 0(a4)
    CHECK a0, 0x66775544
    lw a0, 4(a4)
    CHECK a0, 0x11223344
    FINISH
