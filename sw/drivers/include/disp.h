/* File: disp.h
 * Spec: disp-spec v0.2 2.4, 4.2, 5.3
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_DISP_H
#define EDRV32_DISP_H
#include "engine.h"
/* DISP v0.2 4.2, 5.3: submit RGB565 physical Surface and stride for next VBlank. */
void disp_submit(uint32_t base, uint32_t stride);
/* DISP v0.2 4.2: read current physical Surface; does not acknowledge IRQ. */
uint32_t disp_current(void);
/* DISP v0.2 2.4: read REL_BASE when captured IRQ has SWITCH; release after DMA stops. */
uint32_t disp_released(void);
#endif
