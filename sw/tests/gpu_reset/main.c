/* File: main.c
 * Spec: gpu-soc-testplan ST-14; gpu-soc 5.3, visual SoC 5.3.
 * Description: Request media soft reset and verify GPU/AUD register reset values.
 * Clock domain: clk_sys software, media reset domains observed externally.
 */
#include "../gpu_drivers/test.h"
#include "aud.h"
int main(void)
{
    test_init();
    mmio_write32(EDRV32_GPU_BASE + EDRV32_GPU_TGT_CFG_OFFSET, EDRV32_GPU_TGT_CFG_WIDE_MASK);
    mmio_write32(EDRV32_AUD_BASE + EDRV32_AUD_LOW_LEVEL_OFFSET, 128u);
    test_external(14u);
    sysctrl_write(SYSCTRL_SOFT_RESET, SYSCTRL_RESET_MEDIA);
    /* Harness acknowledges only after observing assertion and synchronous release. */
    while (test_mail()[1] != 2u) {
    }
    test_equal("GPU target reset", EDRV32_GPU_TGT_CFG_RESET,
               mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_TGT_CFG_OFFSET));
    test_equal("AUD low reset", EDRV32_AUD_LOW_LEVEL_RESET,
               mmio_read32(EDRV32_AUD_BASE + EDRV32_AUD_LOW_LEVEL_OFFSET));
    test_equal("GPU idle", EDRV32_GPU_STATUS_RESET,
               mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_STATUS_OFFSET));
    test_equal("AUD disabled", EDRV32_AUD_CTRL_RESET,
               mmio_read32(EDRV32_AUD_BASE + EDRV32_AUD_CTRL_OFFSET));
    uart_puts("PASS ST-14 reset\r\n");
    test_finish(0u);
}
