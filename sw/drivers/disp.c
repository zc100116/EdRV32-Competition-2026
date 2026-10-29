/* File: disp.c
 * Spec: disp-spec v0.2 2.4, 4.2, 5.3
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "disp.h"

/* DISP v0.2 5.3: group shadow writes immediately after FRAME for next VBlank. */
void disp_submit(uint32_t base, uint32_t stride)
{
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_STRIDE_OFFSET, stride);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET, base);
}

/* DISP v0.2 4.2: current Surface must remain owned until SWITCH or stopped IDLE. */
uint32_t disp_current(void)
{
    return mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_CUR_BASE_OFFSET);
}

/* DISP v0.2 2.4: REL_BASE is meaningful when SWITCH was captured, including startup 0. */
uint32_t disp_released(void)
{
    return mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_REL_BASE_OFFSET);
}
