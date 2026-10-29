/* File: perf_mon.h
 * Spec: mem-subsys-spec 2.3, 4.2
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_PERF_MON_H
#define EDRV32_PERF_MON_H
#include "engine.h"
struct perf_mon_config {
    uint32_t mode;
    uint32_t base;
    uint32_t size;
    uint32_t burst_length;
    uint32_t address_mode;
    uint32_t read_ratio;
    uint32_t transactions;
    uint32_t outstanding;
    uint32_t seed;
    uint32_t check;
    uint32_t histogram_width;
};
struct perf_mon_result {
    uint32_t transactions;
    uint32_t beats;
    uint32_t cycles;
    uint32_t latency_min;
    uint32_t latency_max;
    uint32_t latency_sum;
    uint32_t reads;
    uint32_t error_beats;
    uint32_t first_error_address;
    uint32_t histogram[16];
};
/* MEM 2.3, 4.2: configure an idle probe then START; completion is polled (no PLIC source). */
void perf_mon_start(const struct perf_mon_config *config);
/* MEM 4.2: read results after completion, or while stopped following ABORT. */
void perf_mon_read(struct perf_mon_result *result);
#endif
