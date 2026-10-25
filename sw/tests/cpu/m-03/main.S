/* File: m-03/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: FENCE 等待写缓冲排空后提交。
 * Clock: clk_sys. */
#include "test.h"
    START
    la a0, scratch
    li a1, 0x2468ace0
fence_store:
    sw a1, 0(a0)
fence_wait:
    fence rw,rw
after_fence:
    lw a2, 0(a0)
    bne a1, a2, fail
    FINISH
