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
