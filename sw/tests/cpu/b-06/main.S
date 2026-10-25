/* File: b-06/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: 冲刷路径分支不更新 BTB、gshare、GHR、RAS。
 * Clock: clk_sys. */
#include "test.h"
    START
    li a0, 0
    li a1, 16
    li a2, 0
    .balign 8
flush_outer:
    beq zero, zero, flush_target
flushed_branch:
    bne a0, a1, pollution
pollution:
    addi a2, a2, 100
flush_target:
    addi a0, a0, 1
    blt a0, a1, flush_outer
    CHECK a0, 16
    CHECK a2, 0
probe_branch:
    beq a0, a1, probe_done
    j fail
probe_done:
    FINISH
