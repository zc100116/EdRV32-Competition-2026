/* File: main.c
 * Spec: soc-testplan SC-03; SoC 7.3 R3-R6, 8.5-8.8.
 * Description: Capture bypass and mean-filtered 720p frames, hand off locked slots to DISP.
 * Clock domain: clk_sys software.
 */
#include "common.h"
int main(void)
{
    init();
    configure_camera();
    configure_vin(0u, 0u);
    command(1u, 3u);
    while (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(3)) != 1u) {
    }
    equal("bypass slot", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_DONE_INFO_OFFSET(0)));
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0), 1u);
    display(SURFACE_BASE);
    command(2u, 0u);
    write_reg(EDRV32_PIX_BASE, EDRV32_PIX_CFG_OFFSET, 1u << EDRV32_PIX_CFG_S1_OP_POS);
    command(1u, 1u);
    while (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(3)) != 2u) {
    }
    equal("mean slot with slot0 locked", 1u,
          read_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_DONE_INFO_OFFSET(0)));
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0), 3u);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_IRQ_STAT_OFFSET, 0xffffffffu);
    display(SURFACE_BASE + SURFACE_STEP);
    equal("SWITCH", EDRV32_DISP_IRQ_STAT_SWITCH_MASK,
          read_reg(EDRV32_DISP_BASE, EDRV32_DISP_IRQ_STAT_OFFSET) &
          EDRV32_DISP_IRQ_STAT_SWITCH_MASK);
    equal("REL_BASE", SURFACE_BASE, read_reg(EDRV32_DISP_BASE, EDRV32_DISP_REL_BASE_OFFSET));
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0), 2u);
    equal("SLOT_BUSY release", 2u,
          read_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0)));
    command(2u, 1u);
    equal("VIN ERR_CODE", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_ERR_CODE_OFFSET));
    equal("VIN overflow", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(6)));
    equal("DISP underflow", 0u, read_reg(EDRV32_DISP_BASE, EDRV32_DISP_PERF_OFFSET(1)));
    equal("DISP ERR_CODE", 0u, read_reg(EDRV32_DISP_BASE, EDRV32_DISP_ERR_CODE_OFFSET));
    command(99u, 0u);
    finish(0u);
}
