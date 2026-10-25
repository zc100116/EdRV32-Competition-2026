/* File: m-04/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 执行旧代码后改写为返回42，FENCE.I 后必须执行新字节。
 * Clock: clk_sys. */
#include "test.h"
    START
    jal ra, modified_code
    CHECK a0, 1
    la a1, modified_code
    li a2, 0x02a00513
    sw a2, 0(a1)
self_modify_fence:
    fence.i
    jal ra, modified_code
    CHECK a0, 42
    j self_modify_done
    .balign 8
modified_code:
    addi a0, zero, 1
    ret
self_modify_done:
    FINISH
