/* File: npu.c
 * Spec: npu-spec 2.4, 4
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "npu.h"

/* NPU 4: bases/count remain unchanged throughout an inference. */
void npu_configure(const struct npu_config *config)
{
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_MODEL_BASE_OFFSET, config->model);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_WORK_BASE_OFFSET, config->work);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_INPUT_BASE_OFFSET, config->input);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_OUTPUT_BASE_OFFSET, config->output);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_DESC_BASE_OFFSET, config->descriptors);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_DESC_COUNT_OFFSET, config->count);
}

/* NPU 2.4: caller locks VIN input slot and keeps output exclusive until completion. */
void npu_start(uint32_t input, uint32_t output)
{
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_INPUT_BASE_OFFSET, input);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_OUTPUT_BASE_OFFSET, output);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_DOORBELL_OFFSET, 1u);
}

/* NPU 4: index stays at the failing descriptor when ERROR is reported. */
uint32_t npu_current_descriptor(void)
{
    return mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_CUR_DESC_OFFSET);
}

void npu_post_configure(void)
{
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_POST_CTRL_OFFSET,
                 EDRV32_NPU_POST_CTRL_EN_MASK);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_POST_INT8_TH0_OFFSET, 103u);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_POST_INT8_TH1_OFFSET, 105u);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_POST_INT8_TH2_OFFSET, 103u);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_POST_PROB_TH_OFFSET, 4194304u);
}

void npu_post_start(uint32_t input, uint32_t output, uint32_t post)
{
    /* SoC 7.4.4: old CPU sorting may have dirtied any of the 5040 records. */
    engine_dma_clean(EDRV32_DDR_BASE + post, 120960u);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_POST_BASE_OFFSET, post);
    npu_start(input, output);
}

uint32_t npu_post_count(void)
{
    return mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_POST_COUNT_OFFSET);
}

uint32_t npu_post_status(void)
{
    return mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_POST_STATUS_OFFSET);
}

uint32_t npu_post_acquire(uint32_t post)
{
    uint32_t count = npu_post_count();
    /* 4 KiB-aligned base; SoC cache lines are 32 B, including the packed tail. */
    if (count) engine_dma_invalidate(EDRV32_DDR_BASE + post, (count * 24u + 31u) & ~31u);
    return count;
}
