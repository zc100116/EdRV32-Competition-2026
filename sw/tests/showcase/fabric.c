/* fabric.c — SoC 6.4.1 / P5b 9.3; telemetry snapshots inside a benchmark window. */
#include "fabric.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    struct mem_xbar_stats s = {.window_cycles = 100};
    for (unsigned p = 0; p < 7; ++p)
        s.port[p] = (struct mem_xbar_port_stats){p + 1, p + 11, p + 21, p + 31, p + 41, 0, 0};
    board_fabric_sample(&s);
    struct board_fabric_totals before = board_fabric_totals();
    board_fabric_sample(&s); /* Telemetry clears the hardware midway. */
    board_fabric_sample(&s); /* Benchmark's final snapshot. */
    struct board_fabric_totals after = board_fabric_totals();
    assert(after.cycles - before.cycles == 200);
    const uint64_t expected[2][5] = {{10, 50, 30, 70, 90}, {2, 42, 22, 62, 82}};
    for (unsigned p = 0; p < 2; ++p) for (unsigned i = 0; i < 5; ++i)
        assert(after.port[p][i] - before.port[p][i] == expected[p][i]);
    puts("PASS cumulative snapshots retain RND P4 and DISP P0 across telemetry clears");
}
