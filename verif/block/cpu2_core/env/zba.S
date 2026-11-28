/* File: zba.S; Spec: cpu-v2-testplan CV01; Clock: clk_sys. */
#include "riscv_test.h"
#include "test_macros.h"
RVTEST_RV32U
RVTEST_CODE_BEGIN
    li t0, 0x80000001
    li t1, 7
    sh1add t2, t0, t1
    li t3, 9
    li TESTNUM, 2
    bne t2, t3, fail
    sh2add t2, t0, t1
    li t3, 11
    li TESTNUM, 3
    bne t2, t3, fail
    sh3add t2, t0, t1
    li t3, 15
    li TESTNUM, 4
    bne t2, t3, fail
    TEST_PASSFAIL
RVTEST_CODE_END
.data
RVTEST_DATA_BEGIN
RVTEST_DATA_END
