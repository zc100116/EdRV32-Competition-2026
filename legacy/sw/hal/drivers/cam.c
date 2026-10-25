/* ============================================================================
 * File        : cam.c
 * Description : Dual-camera APB HAL implementation.
 * ========================================================================== */
#include "edrv32_cam.h"
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"

#define CAM_ID_OFFSET           0x00u
#define CAM_VERSION_OFFSET      0x04u
#define CAM_CAPABILITY_OFFSET   0x08u
#define CAM_CONTROL_OFFSET      0x0cu
#define CAM_STATUS_OFFSET       0x10u
#define CAM_FRAME0_OFFSET       0x14u
#define CAM_FRAME1_OFFSET       0x18u
#define CAM_IRQ_ENABLE_OFFSET   0x1cu
#define CAM_IRQ_STATUS_OFFSET   0x20u
#define CAM_SCCB_TARGET_OFFSET  0x24u
#define CAM_SCCB_ADDR_OFFSET    0x28u
#define CAM_SCCB_WDATA_OFFSET   0x2cu
#define CAM_SCCB_COMMAND_OFFSET 0x30u
#define CAM_SCCB_STATUS_OFFSET  0x34u
#define CAM_SCCB_RDATA_OFFSET   0x38u

#define CAM_CONTROL_ENABLE0     (1u << 0)
#define CAM_CONTROL_ENABLE1     (1u << 1)

#define CAM_SCCB_COMMAND_SUBMIT (1u << 0)
#define CAM_SCCB_COMMAND_READ   (1u << 1)
#define CAM_SCCB_STATUS_BUSY    (1u << 0)
#define CAM_SCCB_STATUS_DONE    (1u << 1)
#define CAM_SCCB_STATUS_ERROR   (1u << 2)
#define CAM_SCCB_STATUS_READY   (1u << 3)

#define OV5640_AEC_AGC_MANUAL   0x3503u
#define OV5640_EXPOSURE_H       0x3500u
#define OV5640_EXPOSURE_M       0x3501u
#define OV5640_EXPOSURE_L       0x3502u
#define OV5640_GAIN_H           0x350au
#define OV5640_GAIN_L           0x350bu
#define OV5640_AWB_MANUAL       0x3406u
#define OV5640_TIMING_FLIP      0x3820u
#define OV5640_TIMING_MIRROR    0x3821u
#define OV5640_TEST_PATTERN     0x503du

static unsigned char aec_agc_shadow[2] = {0u, 0u};

static unsigned int cam_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_CAM_BASE + offset);
}

static void cam_write(unsigned int offset, unsigned int value)
{
    edrv32_mmio_write32(SOC_CAM_BASE + offset, value);
}

unsigned int edrv32_cam_id(void)
{
    return cam_read(CAM_ID_OFFSET);
}

unsigned int edrv32_cam_version(void)
{
    return cam_read(CAM_VERSION_OFFSET);
}

unsigned int edrv32_cam_capability(void)
{
    return cam_read(CAM_CAPABILITY_OFFSET);
}

int edrv32_cam_set_enabled(unsigned int channel, int enabled)
{
    unsigned int bit;
    unsigned int control;

    if (channel == EDRV32_CAM_CHANNEL0)
        bit = CAM_CONTROL_ENABLE0;
    else if (channel == EDRV32_CAM_CHANNEL1)
        bit = CAM_CONTROL_ENABLE1;
    else
        return -1;

    control = cam_read(CAM_CONTROL_OFFSET);
    if (enabled)
        control |= bit;
    else
        control &= ~bit;
    cam_write(CAM_CONTROL_OFFSET, control);
    return 0;
}

int edrv32_cam_is_enabled(unsigned int channel)
{
    unsigned int control = cam_read(CAM_CONTROL_OFFSET);

    if (channel == EDRV32_CAM_CHANNEL0)
        return (control & CAM_CONTROL_ENABLE0) != 0u;
    if (channel == EDRV32_CAM_CHANNEL1)
        return (control & CAM_CONTROL_ENABLE1) != 0u;
    return -1;
}

void edrv32_cam_set_irq_enable(unsigned int mask)
{
    cam_write(CAM_IRQ_ENABLE_OFFSET, mask & EDRV32_CAM_IRQ_ALL);
}

unsigned int edrv32_cam_get_irq_status(void)
{
    return cam_read(CAM_IRQ_STATUS_OFFSET);
}

void edrv32_cam_clear_irq(unsigned int mask)
{
    cam_write(CAM_IRQ_STATUS_OFFSET, mask & EDRV32_CAM_IRQ_ALL);
}

void edrv32_cam_get_status(struct edrv32_cam_status *status)
{
    if (status == (struct edrv32_cam_status *)0)
        return;
    status->control = cam_read(CAM_CONTROL_OFFSET);
    status->status = cam_read(CAM_STATUS_OFFSET);
    status->frame_count0 = cam_read(CAM_FRAME0_OFFSET);
    status->frame_count1 = cam_read(CAM_FRAME1_OFFSET);
    status->irq_enable = cam_read(CAM_IRQ_ENABLE_OFFSET);
    status->irq_status = cam_read(CAM_IRQ_STATUS_OFFSET);
    status->sccb_status = cam_read(CAM_SCCB_STATUS_OFFSET);
}

unsigned int edrv32_cam_sccb_status(void)
{
    return cam_read(CAM_SCCB_STATUS_OFFSET);
}

int edrv32_cam_write_reg_async(unsigned int channel,
                               unsigned int reg_addr,
                               unsigned int value)
{
    unsigned int status;

    if (channel > EDRV32_CAM_CHANNEL1 || reg_addr > 0xffffu ||
        value > 0xffu)
        return EDRV32_CAM_INVALID;

    status = edrv32_cam_sccb_status();
    if ((status & CAM_SCCB_STATUS_BUSY) != 0u)
        return EDRV32_CAM_BUSY;
    if ((status & CAM_SCCB_STATUS_READY) == 0u)
        return EDRV32_CAM_NOT_READY;

    edrv32_cam_clear_irq(EDRV32_CAM_IRQ_SCCB_DONE |
                         EDRV32_CAM_IRQ_SCCB_ERROR);
    cam_write(CAM_SCCB_TARGET_OFFSET, channel);
    cam_write(CAM_SCCB_ADDR_OFFSET, reg_addr);
    cam_write(CAM_SCCB_WDATA_OFFSET, value);
    cam_write(CAM_SCCB_COMMAND_OFFSET, CAM_SCCB_COMMAND_SUBMIT);
    return EDRV32_CAM_OK;
}

int edrv32_cam_wait_sccb(unsigned int timeout_cycles)
{
    unsigned int status;

    while (timeout_cycles != 0u) {
        status = edrv32_cam_sccb_status();
        if ((status & CAM_SCCB_STATUS_BUSY) == 0u) {
            if ((status & CAM_SCCB_STATUS_ERROR) != 0u)
                return EDRV32_CAM_IO_ERROR;
            if ((status & CAM_SCCB_STATUS_DONE) != 0u)
                return EDRV32_CAM_OK;
        }
        timeout_cycles--;
    }
    return EDRV32_CAM_TIMEOUT;
}

int edrv32_cam_write_reg(unsigned int channel,
                         unsigned int reg_addr,
                         unsigned int value,
                         unsigned int timeout_cycles)
{
    int result = edrv32_cam_write_reg_async(channel, reg_addr, value);

    if (result != EDRV32_CAM_OK)
        return result;
    return edrv32_cam_wait_sccb(timeout_cycles);
}

int edrv32_cam_read_reg_async(unsigned int channel,
                              unsigned int reg_addr)
{
    unsigned int status;

    if (channel > EDRV32_CAM_CHANNEL1 || reg_addr > 0xffffu)
        return EDRV32_CAM_INVALID;

    status = edrv32_cam_sccb_status();
    if ((status & CAM_SCCB_STATUS_BUSY) != 0u)
        return EDRV32_CAM_BUSY;
    if ((status & CAM_SCCB_STATUS_READY) == 0u)
        return EDRV32_CAM_NOT_READY;

    edrv32_cam_clear_irq(EDRV32_CAM_IRQ_SCCB_DONE |
                         EDRV32_CAM_IRQ_SCCB_ERROR);
    cam_write(CAM_SCCB_TARGET_OFFSET, channel);
    cam_write(CAM_SCCB_ADDR_OFFSET, reg_addr);
    cam_write(CAM_SCCB_COMMAND_OFFSET,
              CAM_SCCB_COMMAND_SUBMIT | CAM_SCCB_COMMAND_READ);
    return EDRV32_CAM_OK;
}

int edrv32_cam_read_reg(unsigned int channel,
                        unsigned int reg_addr,
                        unsigned int *value,
                        unsigned int timeout_cycles)
{
    int result;

    if (value == (unsigned int *)0)
        return EDRV32_CAM_INVALID;
    result = edrv32_cam_read_reg_async(channel, reg_addr);
    if (result != EDRV32_CAM_OK)
        return result;
    result = edrv32_cam_wait_sccb(timeout_cycles);
    if (result != EDRV32_CAM_OK)
        return result;
    *value = cam_read(CAM_SCCB_RDATA_OFFSET) & 0xffu;
    return EDRV32_CAM_OK;
}

int edrv32_cam_read_chip_id(unsigned int channel, unsigned int *chip_id,
                            unsigned int timeout_cycles)
{
    unsigned int high;
    unsigned int low;
    int result;

    if (chip_id == (unsigned int *)0)
        return EDRV32_CAM_INVALID;
    result = edrv32_cam_read_reg(channel, 0x300au, &high,
                                 timeout_cycles);
    if (result != EDRV32_CAM_OK)
        return result;
    result = edrv32_cam_read_reg(channel, 0x300bu, &low,
                                 timeout_cycles);
    if (result != EDRV32_CAM_OK)
        return result;
    *chip_id = (high << 8) | low;
    return EDRV32_CAM_OK;
}

static int cam_write_checked(unsigned int channel, unsigned int reg_addr,
                             unsigned int value, unsigned int timeout_cycles)
{
    return edrv32_cam_write_reg(channel, reg_addr, value, timeout_cycles);
}

int edrv32_cam_set_auto_exposure(unsigned int channel, int enabled,
                                 unsigned int timeout_cycles)
{
    if (channel > EDRV32_CAM_CHANNEL1)
        return EDRV32_CAM_INVALID;
    if (enabled)
        aec_agc_shadow[channel] &= (unsigned char)~1u;
    else
        aec_agc_shadow[channel] |= 1u;
    return cam_write_checked(channel, OV5640_AEC_AGC_MANUAL,
                             aec_agc_shadow[channel], timeout_cycles);
}

int edrv32_cam_set_auto_gain(unsigned int channel, int enabled,
                             unsigned int timeout_cycles)
{
    if (channel > EDRV32_CAM_CHANNEL1)
        return EDRV32_CAM_INVALID;
    if (enabled)
        aec_agc_shadow[channel] &= (unsigned char)~2u;
    else
        aec_agc_shadow[channel] |= 2u;
    return cam_write_checked(channel, OV5640_AEC_AGC_MANUAL,
                             aec_agc_shadow[channel], timeout_cycles);
}

int edrv32_cam_set_exposure(unsigned int channel, unsigned int exposure,
                            unsigned int timeout_cycles)
{
    int result;

    if (channel > EDRV32_CAM_CHANNEL1 || exposure > 0xfffffu)
        return EDRV32_CAM_INVALID;
    result = cam_write_checked(channel, OV5640_EXPOSURE_H,
        (exposure >> 12) & 0x0fu, timeout_cycles);
    if (result != EDRV32_CAM_OK)
        return result;
    result = cam_write_checked(channel, OV5640_EXPOSURE_M,
        (exposure >> 4) & 0xffu, timeout_cycles);
    if (result != EDRV32_CAM_OK)
        return result;
    return cam_write_checked(channel, OV5640_EXPOSURE_L,
        (exposure & 0x0fu) << 4, timeout_cycles);
}

int edrv32_cam_set_gain(unsigned int channel, unsigned int gain,
                        unsigned int timeout_cycles)
{
    int result;

    if (channel > EDRV32_CAM_CHANNEL1 || gain > 0x3ffu)
        return EDRV32_CAM_INVALID;
    result = cam_write_checked(channel, OV5640_GAIN_H,
        (gain >> 8) & 0x03u, timeout_cycles);
    if (result != EDRV32_CAM_OK)
        return result;
    return cam_write_checked(channel, OV5640_GAIN_L,
        gain & 0xffu, timeout_cycles);
}

int edrv32_cam_set_auto_white_balance(unsigned int channel, int enabled,
                                      unsigned int timeout_cycles)
{
    return cam_write_checked(channel, OV5640_AWB_MANUAL,
                             enabled ? 0u : 1u, timeout_cycles);
}

int edrv32_cam_set_mirror(unsigned int channel, int enabled,
                          unsigned int timeout_cycles)
{
    return cam_write_checked(channel, OV5640_TIMING_MIRROR,
                             enabled ? 0x07u : 0x01u,
                             timeout_cycles);
}

int edrv32_cam_set_flip(unsigned int channel, int enabled,
                        unsigned int timeout_cycles)
{
    return cam_write_checked(channel, OV5640_TIMING_FLIP,
                             enabled ? 0x40u : 0x46u,
                             timeout_cycles);
}

int edrv32_cam_set_test_pattern(unsigned int channel, int enabled,
                                unsigned int timeout_cycles)
{
    return cam_write_checked(channel, OV5640_TEST_PATTERN,
                             enabled ? 0x80u : 0x00u,
                             timeout_cycles);
}
