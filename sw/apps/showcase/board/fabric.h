/* fabric.h — SoC 6.4.1; cumulative RND P4 / DISP P0 snapshots; clk_sys. */
#ifndef SHOWCASE_FABRIC_H
#define SHOWCASE_FABRIC_H
#include "mem_xbar.h"
struct board_fabric_totals {
    uint64_t cycles;
    uint64_t port[2][5];
};
void board_memory_sample(const struct mem_xbar_stats *sample);
void board_fabric_sample(const struct mem_xbar_stats *sample);
struct board_fabric_totals board_fabric_totals(void);
#endif
