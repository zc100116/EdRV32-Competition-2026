/* File: vin.c
 * Spec: vin-spec 4.2–4.3, 5.1
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "vin.h"

/* VIN 4.2: size is sampled by the selected source at frame start. */
void vin_camera_size(unsigned int camera, unsigned int width, unsigned int height)
{
    uint32_t offset = camera == 0u ? EDRV32_VIN_CAM0_SIZE_OFFSET : EDRV32_VIN_CAM1_SIZE_OFFSET;
    mmio_write32(EDRV32_VIN_BASE + offset,
                 width | (height << EDRV32_VIN_CAM0_SIZE_HEIGHT_POS));
}

/* VIN 4.3: initialize ownership and all active bases before enabling frame reception. */
void vin_channel_configure(unsigned int channel, const struct vin_channel *config)
{
    for (unsigned int slot = 0; slot < config->ring_count; ++slot) {
        mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_SURF_BASE_OFFSET(channel, slot),
                     config->base[slot]);
    }
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_STRIDE_OFFSET(channel), config->stride);
    vin_slots_busy(channel, config->busy_slots);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_CTRL_OFFSET(channel),
                 EDRV32_VIN_CH_CTRL_EN_MASK |
                 ((uint32_t)config->source << EDRV32_VIN_CH_CTRL_SRC_POS) |
                 (config->ring_count << EDRV32_VIN_CH_CTRL_RING_N_POS));
}

/* VIN 5.2: disable stops new frames while a filling frame still completes normally. */
void vin_channel_enable(unsigned int channel, unsigned int enabled)
{
    uintptr_t address = EDRV32_VIN_BASE + EDRV32_VIN_CH_CTRL_OFFSET(channel);
    uint32_t control = mmio_read32(address) & ~EDRV32_VIN_CH_CTRL_EN_MASK;
    mmio_write32(address, control | (enabled << EDRV32_VIN_CH_CTRL_EN_POS));
}

/* VIN 4.3: software maintains the whole bitmap across consumers. */
void vin_slots_busy(unsigned int channel, uint32_t slots)
{
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_SLOT_BUSY_OFFSET(channel), slots);
}

/* VIN 4.3: caller reads within one frame period after the channel IRQ. */
struct vin_frame vin_frame_done(unsigned int channel)
{
    struct vin_frame frame;
    frame.info = mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET(channel));
    frame.frame_id = mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(channel));
    return frame;
}

/* VIN 4.3: preserve other completion flags separately for error reporting. */
unsigned int vin_frame_slot(uint32_t info)
{
    return (info & EDRV32_VIN_CH_DONE_INFO_SLOT_MASK) >> EDRV32_VIN_CH_DONE_INFO_SLOT_POS;
}

/* VIN 4.2: START follows configuration and CPU cache clean if source is CPU-written. */
void vin_memory_start(uint32_t base, uint32_t stride, unsigned int width, unsigned int height)
{
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_MSRC_BASE_OFFSET, base);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_MSRC_STRIDE_OFFSET, stride);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_MSRC_SIZE_OFFSET,
                 width | (height << EDRV32_VIN_MSRC_SIZE_HEIGHT_POS));
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_MSRC_CTRL_OFFSET,
                 EDRV32_VIN_MSRC_CTRL_START_MASK);
}

/* VIN 4.2: memory DONE is distinct from the final destination write response. */
uint32_t vin_memory_status(void)
{
    return mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_MSRC_STAT_OFFSET);
}

/* VIN 4.3: exposes the producer's currently filling slot. */
uint32_t vin_write_status(unsigned int channel)
{
    return mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_CH_WR_STAT_OFFSET(channel));
}
