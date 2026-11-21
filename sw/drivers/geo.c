/* File: geo.c
 * Spec: geo-spec 2.1, 2.6, 4.1
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "geo.h"

_Static_assert(sizeof(struct geo_descriptor) == EDRV32_GEO_DESC_SIZE, "GEO descriptor size");

/* GEO 2.1: integer rational conversion avoids floating-point runtime on RV32IM. */
int32_t geo_q16(int32_t numerator, int32_t denominator)
{
    return (int32_t)((int64_t)numerator * 65536 / denominator);
}

/* GEO 2.6: generated masks preserve byte/pixel field positions and required alignment. */
void geo_descriptor_pack(struct geo_descriptor *descriptor, const struct geo_config *config)
{
    for (unsigned int i = 0; i < EDRV32_GEO_DESC_SIZE / sizeof(uint32_t); ++i) {
        descriptor->word[i] = 0u;
    }
    descriptor->word[EDRV32_GEO_DESC_SRC_BASE_OFFSET / sizeof(uint32_t)] |=
        config->src_base & EDRV32_GEO_DESC_SRC_BASE_MASK;
    descriptor->word[EDRV32_GEO_DESC_SRC_STRIDE_OFFSET / sizeof(uint32_t)] |=
        config->src_stride & EDRV32_GEO_DESC_SRC_STRIDE_MASK;
    descriptor->word[EDRV32_GEO_DESC_SRC_W_OFFSET / sizeof(uint32_t)] |=
        config->src_width & EDRV32_GEO_DESC_SRC_W_MASK;
    descriptor->word[EDRV32_GEO_DESC_SRC_H_OFFSET / sizeof(uint32_t)] |=
        (config->src_height << EDRV32_GEO_DESC_SRC_H_POS) & EDRV32_GEO_DESC_SRC_H_MASK;
    descriptor->word[EDRV32_GEO_DESC_DST_BASE_OFFSET / sizeof(uint32_t)] |=
        config->dst_base & EDRV32_GEO_DESC_DST_BASE_MASK;
    descriptor->word[EDRV32_GEO_DESC_DST_STRIDE_OFFSET / sizeof(uint32_t)] |=
        config->dst_stride & EDRV32_GEO_DESC_DST_STRIDE_MASK;
    descriptor->word[EDRV32_GEO_DESC_RECT_X_OFFSET / sizeof(uint32_t)] |=
        config->rect_x & EDRV32_GEO_DESC_RECT_X_MASK;
    descriptor->word[EDRV32_GEO_DESC_RECT_Y_OFFSET / sizeof(uint32_t)] |=
        (config->rect_y << EDRV32_GEO_DESC_RECT_Y_POS) & EDRV32_GEO_DESC_RECT_Y_MASK;
    descriptor->word[EDRV32_GEO_DESC_RECT_W_OFFSET / sizeof(uint32_t)] |=
        config->rect_width & EDRV32_GEO_DESC_RECT_W_MASK;
    descriptor->word[EDRV32_GEO_DESC_RECT_H_OFFSET / sizeof(uint32_t)] |=
        (config->rect_height << EDRV32_GEO_DESC_RECT_H_POS) & EDRV32_GEO_DESC_RECT_H_MASK;
    descriptor->word[EDRV32_GEO_DESC_BG_OFFSET / sizeof(uint32_t)] |=
        config->background & EDRV32_GEO_DESC_BG_MASK;
    descriptor->word[EDRV32_GEO_DESC_A_OFFSET / sizeof(uint32_t)] =
        (uint32_t)config->matrix[0];
    descriptor->word[EDRV32_GEO_DESC_B_OFFSET / sizeof(uint32_t)] =
        (uint32_t)config->matrix[1];
    descriptor->word[EDRV32_GEO_DESC_TX_OFFSET / sizeof(uint32_t)] =
        (uint32_t)config->matrix[2];
    descriptor->word[EDRV32_GEO_DESC_C_OFFSET / sizeof(uint32_t)] =
        (uint32_t)config->matrix[3];
    descriptor->word[EDRV32_GEO_DESC_D_OFFSET / sizeof(uint32_t)] =
        (uint32_t)config->matrix[4];
    descriptor->word[EDRV32_GEO_DESC_TY_OFFSET / sizeof(uint32_t)] =
        (uint32_t)config->matrix[5];
}

/* GEO 4.1: coherency and exclusive source/destination ownership precede this call. */
void geo_submit(uint32_t descriptors, uint32_t count)
{
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_DESC_BASE_OFFSET, descriptors);
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_DESC_COUNT_OFFSET, count);
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_DOORBELL_OFFSET, 1u);
}

/* GEO 5.1/6: synchronous caller owns completion; the shared IRQ dispatcher must
 * not consume ERROR while this batch is being polled. Restore its IRQ mask afterwards.
 */
uint32_t geo_execute(struct geo_descriptor *table, uint32_t physical, unsigned count)
{
    (void)table;
    uint32_t irq_enable = mmio_read32(EDRV32_GEO_BASE+EDRV32_GEO_IRQ_EN_OFFSET);
    mmio_write32(EDRV32_GEO_BASE+EDRV32_GEO_IRQ_EN_OFFSET,0);
    geo_submit(physical,count);
    struct engine_event event;
    do {
        event = engine_poll(ENGINE_GEO);
    } while (!(event.irq & (EDRV32_GEO_IRQ_STAT_DONE_MASK|
                             EDRV32_GEO_IRQ_STAT_ERROR_MASK)));
    uint32_t error = event.error;
    engine_irq_clear(ENGINE_GEO,event.irq);
    mmio_write32(EDRV32_GEO_BASE+EDRV32_GEO_IRQ_EN_OFFSET,irq_enable);
    return error;
}
