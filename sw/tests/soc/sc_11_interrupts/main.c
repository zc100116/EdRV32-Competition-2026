/* File: main.c
 * Spec: soc-testplan SC-11 (coordinator clarification 74276b8); SoC 6.1.
 * Description: Trigger and claim sources 8-10 and 12-14 exactly once; RND stays pending=0.
 * Clock domain: clk_sys software.
 */
#include "common.h"
static void wait_source(unsigned int source)
{
    while (interrupts[source] == 0u) {
        equal("RND never pending", 0u, plic_pending() & (1u << EDRV32_PLIC_SOURCE_RND));
    }
    equal("source claimed once", 1u, interrupts[source]);
}
int main(void)
{
    init();
    configure_camera();
    configure_vin(0u, 1u);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_IRQ_EN_OFFSET, EDRV32_VIN_IRQ_EN_FRAME_MASK);
    write_reg(EDRV32_PIX_BASE, EDRV32_PIX_IRQ_EN_OFFSET, EDRV32_PIX_IRQ_EN_FRAME_MASK);
    command(1u, 3u);
    wait_source(EDRV32_PLIC_SOURCE_VIN);
    wait_source(EDRV32_PLIC_SOURCE_PIX);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0), 1u);
    run_geo(SURFACE_BASE);
    wait_source(EDRV32_PLIC_SOURCE_GEO);
    display(GEO_BASE);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_IRQ_STAT_OFFSET, 0xffffffffu);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_IRQ_EN_OFFSET, EDRV32_DISP_IRQ_EN_FRAME_MASK);
    wait_source(EDRV32_PLIC_SOURCE_DISP);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_IRQ_EN_OFFSET, 0u);
    while (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(5)) == 0u) {
    }
    configure_npu(CH2_BASE);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_DOORBELL_OFFSET, 1u);
    wait_source(EDRV32_PLIC_SOURCE_NPU);
    configure_eth();
    command(4u, 0u);
    wait_source(EDRV32_PLIC_SOURCE_ETH);
    for (unsigned int source = 8u; source < 15u; source++) {
        equal("PLIC claim/complete coverage", source == EDRV32_PLIC_SOURCE_RND ? 0u : 1u,
              interrupts[source]);
    }
    equal("RND final pending", 0u, plic_pending() & (1u << EDRV32_PLIC_SOURCE_RND));
    command(99u, 0u);
    finish(0u);
}
