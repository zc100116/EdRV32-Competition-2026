/* File: concurrent.c
 * Spec: soc-testplan SC-08/09; SoC 9.1-9.2; mem-subsys 2.3, 4.1.
 * Description: Run camera CH0/CH2, looping NPU, 720p30 ETH and three display scans.
 *              Optionally measure read latency and the shared P6 token-bucket bound.
 * Clock domain: clk_sys software.
 */
#include "common.h"
void concurrent(unsigned int probe)
{
    init();
    configure_camera();
    configure_eth();
    configure_vin(0u, 1u);
    command(1u, 9u);
    while (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(5)) == 0u ||
           read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(3)) == 0u) {
    }
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0), 1u);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(2), 1u);
    configure_npu(CH2_BASE);
    video_descriptors();
    display(SURFACE_BASE);
    write_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_STAT_CTRL_OFFSET,
              EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_MASK);
    if (probe) {
        write_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_BASE_OFFSET, 0x0a200000u);
        write_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_SIZE_OFFSET, 0x100000u);
        write_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_TXN_COUNT_OFFSET, 4096u);
        write_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_CTRL_OFFSET,
                  EDRV32_PERF_MON_CTRL_START_MASK);
    }
    uint64_t next_video = 0u;
    unsigned int npu_started = 0u;
    unsigned int video_started = 0u;
    while (read_reg(EDRV32_DISP_BASE, EDRV32_DISP_PERF_OFFSET(0)) < 3u || npu_started < 2u) {
        if ((read_reg(EDRV32_NPU_BASE, EDRV32_NPU_STATUS_OFFSET) &
             EDRV32_NPU_STATUS_IDLE_MASK) != 0u) {
            write_reg(EDRV32_NPU_BASE, EDRV32_NPU_DOORBELL_OFFSET, 1u);
            npu_started++;
        }
        uint64_t time = clint_time();
        if (time >= next_video && (read_reg(EDRV32_ETH_BASE, EDRV32_ETH_STATUS_OFFSET) &
                                  EDRV32_ETH_STATUS_IDLE_MASK) != 0u) {
            eth_send(TX_DESC, 2u);
            video_started++;
            next_video = time + EDRV32_CLK_SYS_HZ / 30u;
        }
    }
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CTRL_OFFSET, 0u);
    while ((read_reg(EDRV32_VIN_BASE, EDRV32_VIN_STATUS_OFFSET) &
            EDRV32_VIN_STATUS_IDLE_MASK) == 0u ||
           (read_reg(EDRV32_NPU_BASE, EDRV32_NPU_STATUS_OFFSET) &
            EDRV32_NPU_STATUS_IDLE_MASK) == 0u ||
           (read_reg(EDRV32_ETH_BASE, EDRV32_ETH_STATUS_OFFSET) &
            EDRV32_ETH_STATUS_IDLE_MASK) == 0u) {
    }
    equal("NPU completed loops", npu_started,
          read_reg(EDRV32_NPU_BASE, EDRV32_NPU_DONE_COUNT_OFFSET));
    equal("ETH completed video descriptors", video_started * 2u,
          read_reg(EDRV32_ETH_BASE, EDRV32_ETH_DONE_COUNT_OFFSET));
    equal("VIN CH0 overflow", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(6)));
    equal("VIN CH2 overflow", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(8)));
    equal("DISP empty frames", 0u, read_reg(EDRV32_DISP_BASE, EDRV32_DISP_PERF_OFFSET(1)));
    snapshot(0u);
    if (probe) {
        while ((read_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_STATUS_OFFSET) &
                EDRV32_PERF_MON_STATUS_IDLE_MASK) == 0u) {
        }
        uint32_t count = read_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_READ_CNT_OFFSET);
        uint32_t hist_sum = 0u;
        for (unsigned int i = 0; i < 16; i++) {
            hist_sum += read_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_HIST_OFFSET(i));
        }
        equal("histogram sum", count, hist_sum);
        equal("probe completed count", 4096u, count);
        uint32_t sum = read_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_LAT_SUM_OFFSET);
        uint32_t min = read_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_LAT_MIN_OFFSET);
        uint32_t max = read_reg(EDRV32_PERF_MON_BASE, EDRV32_PERF_MON_LAT_MAX_OFFSET);
        equal("LAT_MIN <= mean", 1u, (uint64_t)min * count <= sum);
        equal("mean <= LAT_MAX", 1u, (uint64_t)max * count >= sum);
        uint32_t cycles = read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_WINDOW_CYC_OFFSET);
        uint32_t rate = read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_RATE_OFFSET(6));
        uint32_t beats = read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_RD_BEAT_OFFSET(6));
        uint32_t bound = (uint32_t)((uint64_t)cycles * rate / 256u) + 32u;
        equal("P6 RATE includes initial 32-token bucket", 1u, beats <= bound);
    }
    command(99u, 0u);
    finish(0u);
}
