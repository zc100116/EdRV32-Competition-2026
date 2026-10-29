/* File: perf_mon.c
 * Spec: mem-subsys-spec 2.3, 4.2
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "perf_mon.h"

/* MEM 4.2: caller keeps configuration unchanged until DONE or drained ABORT. */
void perf_mon_start(const struct perf_mon_config *config)
{
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_MODE_OFFSET,
                 config->mode);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_BASE_OFFSET,
                 config->base);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_SIZE_OFFSET,
                 config->size);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_BURST_LEN_OFFSET,
                 config->burst_length);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_ADDR_MODE_OFFSET,
                 config->address_mode);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_RW_RATIO_OFFSET,
                 config->read_ratio);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_TXN_COUNT_OFFSET,
                 config->transactions);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_OUTSTANDING_OFFSET,
                 config->outstanding);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_SEED_OFFSET,
                 config->seed);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_CHECK_EN_OFFSET,
                 config->check);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_HIST_WIDTH_OFFSET,
                 config->histogram_width);
    mmio_write32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_CTRL_OFFSET,
                 EDRV32_PERF_MON_CTRL_START_MASK);
}

/* MEM 4.2: saturated counters and read-check errors are returned without interpretation. */
void perf_mon_read(struct perf_mon_result *result)
{
    result->transactions =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_TXN_DONE_OFFSET);
    result->beats =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_BEATS_OFFSET);
    result->cycles =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_CYCLES_OFFSET);
    result->latency_min =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_LAT_MIN_OFFSET);
    result->latency_max =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_LAT_MAX_OFFSET);
    result->latency_sum =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_LAT_SUM_OFFSET);
    result->reads =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_READ_CNT_OFFSET);
    result->error_beats =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_ERR_BEATS_OFFSET);
    result->first_error_address =
        mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_FIRST_ERR_ADDR_OFFSET);
    for (unsigned int bin = 0; bin < 16u; ++bin) {
        result->histogram[bin] =
            mmio_read32(EDRV32_PERF_MON_BASE + EDRV32_PERF_MON_HIST_OFFSET(bin));
    }
}
