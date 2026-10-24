/* ============================================================================
 * File        : pixel.c
 * Description : Pixel Pipeline APB HAL implementation.
 * ========================================================================== */
#include "edrv32_mmio.h"
#include "edrv32_pixel.h"
#include "edrv32_soc_map.h"

#define PIXEL_ID_OFFSET          0x00u
#define PIXEL_VERSION_OFFSET     0x04u
#define PIXEL_CAPABILITY_OFFSET  0x08u
#define PIXEL_CONTROL_OFFSET     0x0cu
#define PIXEL_BRIGHTNESS_OFFSET  0x10u
#define PIXEL_CONTRAST_OFFSET    0x14u
#define PIXEL_THRESHOLD_OFFSET   0x18u
#define PIXEL_COMMAND_OFFSET     0x1cu
#define PIXEL_STATUS_OFFSET      0x20u
#define PIXEL_FRAME_COUNT_OFFSET 0x24u
#define PIXEL_ERROR_COUNT_OFFSET 0x28u
#define PIXEL_IRQ_ENABLE_OFFSET  0x2cu
#define PIXEL_IRQ_STATUS_OFFSET  0x30u
#define PIXEL_SPATIAL_CONTROL_OFFSET   0x34u
#define PIXEL_SPATIAL_THRESHOLD_OFFSET 0x38u

#define PIXEL_CONTROL_ENABLE    (1u << 0)
#define PIXEL_CONTROL_GRAYSCALE (1u << 1)
#define PIXEL_CONTROL_THRESHOLD (1u << 2)
#define PIXEL_CONTROL_INVERT    (1u << 3)
#define PIXEL_COMMAND_COMMIT    (1u << 0)
#define PIXEL_SPATIAL_ENABLE    (1u << 0)
#define PIXEL_SPATIAL_MODE_SHIFT 1u

static unsigned int pixel_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_PIXEL_BASE + offset);
}

static void pixel_write(unsigned int offset, unsigned int value)
{
    edrv32_mmio_write32(SOC_PIXEL_BASE + offset, value);
}

unsigned int edrv32_pixel_id(void)
{
    return pixel_read(PIXEL_ID_OFFSET);
}

unsigned int edrv32_pixel_version(void)
{
    return pixel_read(PIXEL_VERSION_OFFSET);
}

unsigned int edrv32_pixel_capability(void)
{
    return pixel_read(PIXEL_CAPABILITY_OFFSET);
}

unsigned int edrv32_pixel_status(void)
{
    return pixel_read(PIXEL_STATUS_OFFSET);
}

unsigned int edrv32_pixel_frame_count(void)
{
    return pixel_read(PIXEL_FRAME_COUNT_OFFSET);
}

unsigned int edrv32_pixel_error_count(void)
{
    return pixel_read(PIXEL_ERROR_COUNT_OFFSET);
}

int edrv32_pixel_configure(const struct edrv32_pixel_config *config)
{
    unsigned int control = 0u;

    if (config == (const struct edrv32_pixel_config *)0 ||
        config->brightness < -256 || config->brightness > 255 ||
        config->contrast_q8 > 511u || config->threshold > 255u ||
        config->spatial_mode > EDRV32_PIXEL_SPATIAL_DILATE ||
        config->spatial_threshold > 255u)
        return -1;

    if (config->enable)
        control |= PIXEL_CONTROL_ENABLE;
    if (config->grayscale)
        control |= PIXEL_CONTROL_GRAYSCALE;
    if (config->threshold_enable)
        control |= PIXEL_CONTROL_THRESHOLD;
    if (config->invert)
        control |= PIXEL_CONTROL_INVERT;

    pixel_write(PIXEL_CONTROL_OFFSET, control);
    pixel_write(PIXEL_BRIGHTNESS_OFFSET,
                (unsigned int)config->brightness & 0x1ffu);
    pixel_write(PIXEL_CONTRAST_OFFSET, config->contrast_q8);
    pixel_write(PIXEL_THRESHOLD_OFFSET, config->threshold);
    pixel_write(PIXEL_SPATIAL_CONTROL_OFFSET,
                (config->spatial_enable ? PIXEL_SPATIAL_ENABLE : 0u) |
                (config->spatial_mode << PIXEL_SPATIAL_MODE_SHIFT));
    pixel_write(PIXEL_SPATIAL_THRESHOLD_OFFSET,
                config->spatial_threshold);
    return 0;
}

void edrv32_pixel_commit(void)
{
    pixel_write(PIXEL_COMMAND_OFFSET, PIXEL_COMMAND_COMMIT);
}

void edrv32_pixel_set_irq_enable(unsigned int mask)
{
    pixel_write(PIXEL_IRQ_ENABLE_OFFSET, mask & EDRV32_PIXEL_IRQ_ALL);
}

unsigned int edrv32_pixel_get_irq_status(void)
{
    return pixel_read(PIXEL_IRQ_STATUS_OFFSET);
}

void edrv32_pixel_clear_irq(unsigned int mask)
{
    pixel_write(PIXEL_IRQ_STATUS_OFFSET, mask & EDRV32_PIXEL_IRQ_ALL);
}
