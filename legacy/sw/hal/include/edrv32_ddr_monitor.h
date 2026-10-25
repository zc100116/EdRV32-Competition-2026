/* ============================================================================
 * File        : edrv32_ddr_monitor.h
 * Description : Register contract for the APB-controlled DDR traffic monitor.
 * Notes       : base_addr is a physical DDR byte offset, not 0x80000000 plus
 *               an offset. Transfers are 32-byte aligned 256-bit AXI beats.
 * ========================================================================== */
#ifndef EDRV32_DDR_MONITOR_H
#define EDRV32_DDR_MONITOR_H

#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"

#define EDRV32_DDR_MON_ID                 0x00u
#define EDRV32_DDR_MON_VERSION            0x04u
#define EDRV32_DDR_MON_CONTROL            0x08u
#define EDRV32_DDR_MON_STATUS             0x0cu
#define EDRV32_DDR_MON_MODE               0x10u
#define EDRV32_DDR_MON_BASE_ADDR          0x14u
#define EDRV32_DDR_MON_TOTAL_BEATS        0x18u
#define EDRV32_DDR_MON_BURST_LEN          0x1cu /* AxLEN, hardware caps at 15 */
#define EDRV32_DDR_MON_PATTERN_SEED       0x20u
#define EDRV32_DDR_MON_LOOP_COUNT         0x24u
#define EDRV32_DDR_MON_TOTAL_CYCLES       0x30u
#define EDRV32_DDR_MON_WRITE_BEATS        0x34u
#define EDRV32_DDR_MON_READ_BEATS         0x38u
#define EDRV32_DDR_MON_AW_STALL_CYCLES    0x3cu
#define EDRV32_DDR_MON_W_STALL_CYCLES     0x40u
#define EDRV32_DDR_MON_AR_STALL_CYCLES    0x44u
#define EDRV32_DDR_MON_R_WAIT_CYCLES      0x48u
#define EDRV32_DDR_MON_ERROR_COUNT        0x4cu
#define EDRV32_DDR_MON_FIRST_ERROR_ADDR   0x50u
#define EDRV32_DDR_MON_EXPECTED_DATA      0x54u
#define EDRV32_DDR_MON_ACTUAL_DATA        0x58u

#define EDRV32_DDR_MON_CONTROL_START      (1u << 0)
#define EDRV32_DDR_MON_CONTROL_CLEAR      (1u << 1)
#define EDRV32_DDR_MON_STATUS_BUSY        (1u << 0)
#define EDRV32_DDR_MON_STATUS_DONE        (1u << 1)
#define EDRV32_DDR_MON_STATUS_ERROR       (1u << 2)
#define EDRV32_DDR_MON_STATUS_CMD_READY   (1u << 3)

#define EDRV32_DDR_MON_MODE_WRITE         0u
#define EDRV32_DDR_MON_MODE_READ_VERIFY   1u
#define EDRV32_DDR_MON_MODE_WRITE_READ    2u
#define EDRV32_DDR_MON_MAX_BURST_LEN      15u

struct edrv32_ddr_monitor_result {
    unsigned int total_cycles;
    unsigned int write_beats;
    unsigned int read_beats;
    unsigned int aw_stall_cycles;
    unsigned int w_stall_cycles;
    unsigned int ar_stall_cycles;
    unsigned int r_wait_cycles;
    unsigned int error_count;
    unsigned int first_error_addr;
    unsigned int expected_data;
    unsigned int actual_data;
};

static inline void edrv32_ddr_monitor_write(unsigned int offset,
                                             unsigned int value)
{
    edrv32_mmio_write32(SOC_DDR_MONITOR_BASE + offset, value);
}

static inline unsigned int edrv32_ddr_monitor_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_DDR_MONITOR_BASE + offset);
}

static inline void edrv32_ddr_monitor_start(unsigned int mode,
                                             unsigned int base_addr,
                                             unsigned int total_beats,
                                             unsigned int burst_len,
                                             unsigned int pattern_seed,
                                             unsigned int loop_count)
{
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_MODE, mode);
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_BASE_ADDR, base_addr);
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_TOTAL_BEATS, total_beats);
    if (burst_len > EDRV32_DDR_MON_MAX_BURST_LEN)
        burst_len = EDRV32_DDR_MON_MAX_BURST_LEN;
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_BURST_LEN, burst_len);
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_PATTERN_SEED, pattern_seed);
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_LOOP_COUNT, loop_count);
    edrv32_ddr_monitor_write(EDRV32_DDR_MON_CONTROL,
                             EDRV32_DDR_MON_CONTROL_START);
}

static inline void edrv32_ddr_monitor_get_result(
    struct edrv32_ddr_monitor_result *result)
{
    result->total_cycles = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_TOTAL_CYCLES);
    result->write_beats = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_WRITE_BEATS);
    result->read_beats = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_READ_BEATS);
    result->aw_stall_cycles = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_AW_STALL_CYCLES);
    result->w_stall_cycles = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_W_STALL_CYCLES);
    result->ar_stall_cycles = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_AR_STALL_CYCLES);
    result->r_wait_cycles = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_R_WAIT_CYCLES);
    result->error_count = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_ERROR_COUNT);
    result->first_error_addr = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_FIRST_ERROR_ADDR);
    result->expected_data = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_EXPECTED_DATA);
    result->actual_data = edrv32_ddr_monitor_read(
        EDRV32_DDR_MON_ACTUAL_DATA);
}

#endif /* EDRV32_DDR_MONITOR_H */
