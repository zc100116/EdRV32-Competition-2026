/* File: c-04/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: time/timeh 只读返回外部64位 mtime_i。
 * Clock: clk_sys. */
#include "test.h"
    START
    csrr a0, time
    csrr a1, timeh
#ifndef SPIKE_SMOKE
    CHECK a0, 0x89abcdef
    CHECK a1, 0x01234567
#endif
    csrr a2, time
    csrr a3, timeh
#ifndef SPIKE_SMOKE
    CHECK a2, 0x89abcdef
    CHECK a3, 0x01234567
#endif
    FINISH
