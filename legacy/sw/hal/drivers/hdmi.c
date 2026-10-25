/* ============================================================================
 * File        : hdmi.c
 * Description : HDMI display APB HAL implementation.
 * ========================================================================== */
#include "edrv32_hdmi.h"
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"

#define HDMI_ID_OFFSET              0x00u
#define HDMI_VERSION_OFFSET         0x04u
#define HDMI_CAPABILITY_OFFSET      0x08u
#define HDMI_CONTROL_OFFSET         0x0cu
#define HDMI_STATUS_OFFSET          0x10u
#define HDMI_FRAME_COUNT_OFFSET     0x14u
#define HDMI_UNDERFLOW_COUNT_OFFSET 0x18u
#define HDMI_BUFFER0_OFFSET         0x1cu
#define HDMI_BUFFER1_OFFSET         0x20u
#define HDMI_BUFFER2_OFFSET         0x24u
#define HDMI_IRQ_ENABLE_OFFSET      0x28u
#define HDMI_IRQ_STATUS_OFFSET      0x2cu
#define HDMI_SCANOUT_FRAMES_OFFSET  0x30u
#define HDMI_DEBUG_STATUS_OFFSET    0x34u

#define HDMI_CONTROL_ENABLE         (1u << 0)
#define HDMI_STATUS_ACTIVE_LSB      1u

static unsigned int hdmi_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_DISP_BASE + offset);
}

static void hdmi_write(unsigned int offset, unsigned int value)
{
    edrv32_mmio_write32(SOC_DISP_BASE + offset, value);
}

unsigned int edrv32_hdmi_id(void)
{
    return hdmi_read(HDMI_ID_OFFSET);
}

unsigned int edrv32_hdmi_version(void)
{
    return hdmi_read(HDMI_VERSION_OFFSET);
}

unsigned int edrv32_hdmi_capability(void)
{
    return hdmi_read(HDMI_CAPABILITY_OFFSET);
}

void edrv32_hdmi_set_enabled(int enabled)
{
    hdmi_write(HDMI_CONTROL_OFFSET,
               enabled ? HDMI_CONTROL_ENABLE : 0u);
}

int edrv32_hdmi_is_enabled(void)
{
    return (hdmi_read(HDMI_CONTROL_OFFSET) & HDMI_CONTROL_ENABLE) != 0u;
}

unsigned int edrv32_hdmi_active_buffer(void)
{
    return (hdmi_read(HDMI_STATUS_OFFSET) >> HDMI_STATUS_ACTIVE_LSB) & 3u;
}

unsigned int edrv32_hdmi_buffer_base(unsigned int index)
{
    if (index == 0u)
        return hdmi_read(HDMI_BUFFER0_OFFSET);
    if (index == 1u)
        return hdmi_read(HDMI_BUFFER1_OFFSET);
    if (index == 2u)
        return hdmi_read(HDMI_BUFFER2_OFFSET);
    return 0u;
}

void edrv32_hdmi_set_irq_enable(unsigned int mask)
{
    hdmi_write(HDMI_IRQ_ENABLE_OFFSET, mask & EDRV32_HDMI_IRQ_ALL);
}

unsigned int edrv32_hdmi_get_irq_status(void)
{
    return hdmi_read(HDMI_IRQ_STATUS_OFFSET);
}

void edrv32_hdmi_clear_irq(unsigned int mask)
{
    hdmi_write(HDMI_IRQ_STATUS_OFFSET, mask & EDRV32_HDMI_IRQ_ALL);
}

void edrv32_hdmi_get_status(struct edrv32_hdmi_status *status)
{
    if (status == (struct edrv32_hdmi_status *)0)
        return;
    status->control = hdmi_read(HDMI_CONTROL_OFFSET);
    status->status = hdmi_read(HDMI_STATUS_OFFSET);
    status->frame_count = hdmi_read(HDMI_FRAME_COUNT_OFFSET);
    status->underflow_count = hdmi_read(HDMI_UNDERFLOW_COUNT_OFFSET);
    status->buffer_base[0] = hdmi_read(HDMI_BUFFER0_OFFSET);
    status->buffer_base[1] = hdmi_read(HDMI_BUFFER1_OFFSET);
    status->buffer_base[2] = hdmi_read(HDMI_BUFFER2_OFFSET);
    status->irq_enable = hdmi_read(HDMI_IRQ_ENABLE_OFFSET);
    status->irq_status = hdmi_read(HDMI_IRQ_STATUS_OFFSET);
    status->scanout_frame_count = hdmi_read(HDMI_SCANOUT_FRAMES_OFFSET);
    status->debug_status = hdmi_read(HDMI_DEBUG_STATUS_OFFSET);
}
