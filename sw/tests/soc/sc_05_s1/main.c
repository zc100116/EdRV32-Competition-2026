/* File: main.c
 * Spec: soc-testplan SC-05; VIN 2.3, 2.8, 5.1; NPU 2.4.
 * Description: Split the preloaded full RGB565 frame to CH0/CH2 and execute three NPU layers.
 * Clock domain: clk_sys software.
 */
#include "common.h"
int main(void)
{
    init();
    configure_vin(2u, 1u);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_MSRC_BASE_OFFSET, IMAGE_BASE);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_MSRC_CTRL_OFFSET, EDRV32_VIN_MSRC_CTRL_START_MASK);
    while (read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(5)) != 1u ||
           read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(3)) != 1u) {
        equal("VIN CH2 overflow", 0u,
              read_reg(EDRV32_VIN_BASE, EDRV32_VIN_PERF_OFFSET(8)));
        equal("VIN ERR_CODE", 0u, read_reg(EDRV32_VIN_BASE, EDRV32_VIN_ERR_CODE_OFFSET));
    }
    equal("CH0/CH2 frame_id", read_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(0)),
          read_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(2)));
    wait_irq(EDRV32_PLIC_SOURCE_VIN, 1u);
    equal("VIN CH0/CH2 IRQ", EDRV32_VIN_IRQ_STAT_FRAME_MASK |
          EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK,
          events[EDRV32_PLIC_SOURCE_VIN] &
          (EDRV32_VIN_IRQ_STAT_FRAME_MASK | EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK));
    command(3u, CH2_BASE);
    configure_npu(CH2_BASE);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_DOORBELL_OFFSET, 1u);
    wait_irq(EDRV32_PLIC_SOURCE_NPU, 1u);
    equal("NPU ERR_CODE", 0u, read_reg(EDRV32_NPU_BASE, EDRV32_NPU_ERR_CODE_OFFSET));
    equal("NPU DONE_COUNT", 1u, read_reg(EDRV32_NPU_BASE, EDRV32_NPU_DONE_COUNT_OFFSET));
    command(5u, NPU_OUTPUT);
    command(99u, 0u);
    finish(0u);
}
