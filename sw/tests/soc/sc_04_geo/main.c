/* File: main.c
 * Spec: soc-testplan SC-04; SoC 7.3, 8.7.
 * Description: Capture one 720p base frame, rotate 45 degrees at s=1, display GEO output.
 * Clock domain: clk_sys software.
 */
#include "common.h"
int main(void)
{
    init();
    configure_camera();
    configure_vin(0u, 0u);
    command(1u, 3u);
    wait_irq(EDRV32_PLIC_SOURCE_VIN, 1u);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0), 1u);
    run_geo(SURFACE_BASE);
    wait_irq(EDRV32_PLIC_SOURCE_GEO, 1u);
    equal("GEO DONE", EDRV32_GEO_IRQ_STAT_DONE_MASK,
          events[EDRV32_PLIC_SOURCE_GEO] & EDRV32_GEO_IRQ_STAT_DONE_MASK);
    equal("GEO ERR_CODE", 0u, read_reg(EDRV32_GEO_BASE, EDRV32_GEO_ERR_CODE_OFFSET));
    display(GEO_BASE);
    command(2u, 2u);
    command(99u, 0u);
    finish(0u);
}
