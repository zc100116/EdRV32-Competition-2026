/* File: mem_xbar.h
 * Spec: mem-subsys-spec 4.1
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_MEM_XBAR_H
#define EDRV32_MEM_XBAR_H
#include "engine.h"
struct mem_xbar_port_stats {
    uint32_t rd_txn;
    uint32_t rd_beat;
    uint32_t wr_txn;
    uint32_t wr_beat;
    uint32_t wait_sum;
    uint32_t wait_max;
    uint32_t urgent;
};
struct mem_xbar_stats {
    uint32_t window_cycles;
    uint32_t downstream_busy;
    uint32_t direction_switches;
    struct mem_xbar_port_stats port[7];
};
/* MEM 4.1: SNAPSHOT|CLEAR atomically then read the frozen global and P0–P6 counters. */
void mem_xbar_snapshot(struct mem_xbar_stats *stats);
/* MEM 4.1: configure RATE[p] (1/256 beat/cycle, effective for P2 and P6). */
void mem_xbar_rate(unsigned int port, uint32_t rate);
/* MEM 4.1: read most recent violation details before clearing engine ERROR. */
void mem_xbar_error(uint32_t *port, uint32_t *address, uint32_t *type);
#endif
