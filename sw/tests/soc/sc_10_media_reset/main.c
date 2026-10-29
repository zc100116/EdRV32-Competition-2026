/* File: main.c
 * Spec: soc-testplan SC-10 (coordinator clarification 493779a); sys-subsys 2.10.
 * Description: Stop concurrent S2/GEO/RX, drain, reset media and verify DDR and HDMI recovery.
 * Clock domain: clk_sys software.
 */
#include "common.h"
static void idle(void)
{
    while ((read_reg(EDRV32_VIN_BASE, EDRV32_VIN_STATUS_OFFSET) &
            EDRV32_VIN_STATUS_IDLE_MASK) == 0u ||
           (read_reg(EDRV32_PIX_BASE, EDRV32_PIX_STATUS_OFFSET) &
            EDRV32_PIX_STATUS_IDLE_MASK) == 0u ||
           (read_reg(EDRV32_GEO_BASE, EDRV32_GEO_STATUS_OFFSET) &
            EDRV32_GEO_STATUS_IDLE_MASK) == 0u ||
           (read_reg(EDRV32_DISP_BASE, EDRV32_DISP_STATUS_OFFSET) &
            EDRV32_DISP_STATUS_IDLE_MASK) == 0u ||
           (read_reg(EDRV32_ETH_BASE, EDRV32_ETH_STATUS_OFFSET) &
            EDRV32_ETH_STATUS_IDLE_MASK) == 0u) {
    }
}
int main(void)
{
    init();
    configure_camera();
    configure_eth();
    configure_vin(0u, 0u);
    command(1u, 3u);
    wait_irq(EDRV32_PLIC_SOURCE_VIN, 1u);
    display(SURFACE_BASE);
    run_geo(SURFACE_BASE);
    command(1u, 1u);
    command(4u, 0u);
    while (read_reg(EDRV32_ETH_BASE, EDRV32_ETH_PERF_OFFSET(1)) == 0u ||
           (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_STATUS_OFFSET) &
            EDRV32_VIN_STATUS_BUSY_MASK) == 0u) {
    }
    equal("GEO active with S2/RX", EDRV32_GEO_STATUS_BUSY_MASK,
          read_reg(EDRV32_GEO_BASE, EDRV32_GEO_STATUS_OFFSET) & EDRV32_GEO_STATUS_BUSY_MASK);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CTRL_OFFSET, EDRV32_VIN_CTRL_ABORT_MASK);
    write_reg(EDRV32_PIX_BASE, EDRV32_PIX_CTRL_OFFSET, EDRV32_PIX_CTRL_ABORT_MASK);
    write_reg(EDRV32_GEO_BASE, EDRV32_GEO_CTRL_OFFSET, EDRV32_GEO_CTRL_ABORT_MASK);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_CTRL_OFFSET, EDRV32_DISP_CTRL_ABORT_MASK);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_CTRL_OFFSET, 0u);
    command(9u, 0u);
    command(8u, 0u);
    idle();
    sysctrl_write(SYSCTRL_SOFT_RESET, SYSCTRL_RESET_MEDIA);
    uint64_t release = clint_time() + 64u;
    while (clint_time() < release) {
    }
    idle();
    equal("NPU idle after MEDIA", EDRV32_NPU_STATUS_IDLE_MASK,
          read_reg(EDRV32_NPU_BASE, EDRV32_NPU_STATUS_OFFSET));
    while ((read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_STATUS_OFFSET) &
            EDRV32_MEM_XBAR_STATUS_IDLE_MASK) == 0u) {
    }
    for (unsigned int i = 0; i < 16u; i++) {
        ddr(TX_BASE)[i] = 0x91827300u + i;
        equal("DDR after MEDIA", 0x91827300u + i, ddr(TX_BASE)[i]);
    }
    configure_camera();
    configure_vin(0u, 0u);
    command(1u, 3u);
    while (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_DONE_COUNT_OFFSET) == 0u) {
    }
    display(SURFACE_BASE);
    command(2u, 0u);
    equal("VIN recovered overflow", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(6)));
    equal("DISP recovered empty", 0u, read_reg(EDRV32_DISP_BASE, EDRV32_DISP_PERF_OFFSET(1)));
    command(99u, 0u);
    finish(0u);
}
