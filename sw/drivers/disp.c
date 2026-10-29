/* File: disp.c
 * Spec: disp-spec v0.3 2.4, 2.7, 4.2, 5.3.
 * Description: Shadow configuration and per-layer Surface ownership observations.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "disp.h"

void disp_submit(enum disp_layer layer, uint32_t base, uint32_t stride)
{
    const uint32_t strides[] = {EDRV32_DISP_STRIDE_OFFSET, EDRV32_DISP_L1_STRIDE_OFFSET};
    const uint32_t bases[] = {EDRV32_DISP_NEXT_BASE_OFFSET, EDRV32_DISP_L1_NEXT_BASE_OFFSET};
    mmio_write32(EDRV32_DISP_BASE + strides[layer], stride);
    mmio_write32(EDRV32_DISP_BASE + bases[layer], base);
}

void disp_layer_enable(enum disp_layer layer, unsigned int enable)
{
    const uint32_t bits[] = {EDRV32_DISP_LAYER_CTRL_L0_EN_MASK,
                             EDRV32_DISP_LAYER_CTRL_L1_EN_MASK};
    uint32_t value = mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET);
    value = (value & ~bits[layer]) | (enable ? bits[layer] : 0u);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET, value);
}

void disp_l0_scroll(uint16_t x, uint16_t y)
{
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_L0_SCROLL_OFFSET,
                 ((uint32_t)x << EDRV32_DISP_L0_SCROLL_SCROLL_X_POS) |
                 ((uint32_t)y << EDRV32_DISP_L0_SCROLL_SCROLL_Y_POS));
}

void disp_l1_geometry(uint16_t x, uint16_t y, uint16_t width, uint16_t height, uint8_t opa)
{
    /* X/W are pixel coordinates, including the three zero low bits (4.2). */
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_L1_POS_OFFSET,
                 x | ((uint32_t)y << EDRV32_DISP_L1_POS_Y_POS));
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_L1_SIZE_OFFSET,
                 width | ((uint32_t)height << EDRV32_DISP_L1_SIZE_H_POS));
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_L1_OPA_OFFSET, opa);
}

uint32_t disp_current(enum disp_layer layer)
{
    const uint32_t offsets[] = {EDRV32_DISP_CUR_BASE_OFFSET, EDRV32_DISP_L1_CUR_BASE_OFFSET};
    return mmio_read32(EDRV32_DISP_BASE + offsets[layer]);
}

uint32_t disp_switched(enum disp_layer layer)
{
    const uint32_t bits[] = {EDRV32_DISP_IRQ_STAT_SWITCH_MASK, EDRV32_DISP_IRQ_STAT_SWITCH1_MASK};
    return mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_IRQ_STAT_OFFSET) & bits[layer];
}

uint32_t disp_released(enum disp_layer layer)
{
    const uint32_t offsets[] = {EDRV32_DISP_REL_BASE_OFFSET, EDRV32_DISP_L1_REL_BASE_OFFSET};
    return mmio_read32(EDRV32_DISP_BASE + offsets[layer]);
}
