/* File: i2c.c
 * Spec: sys-subsys-spec 2.8, 4.5
 * Description: Blocking byte commands and SCCB helpers with 16-bit register addresses.
 * Clock domain: clk_sys.
 */
#include "i2c.h"

void i2c_init(unsigned int port, uint32_t clock_hz, uint32_t scl_hz)
{
    while ((mmio_read32(EDRV32_I2C0_BASE + I2C_STATUS) & I2C_STATUS_BUSY) != 0u) {
    }
    mmio_write32(EDRV32_I2C0_BASE + I2C_CLK_DIV, clock_hz / (4u * scl_hz) - 1u);
    mmio_write32(EDRV32_I2C0_BASE + I2C_CTRL, I2C_CTRL_EN | (port << 1));
}

int i2c_command(uint32_t command)
{
    while ((mmio_read32(EDRV32_I2C0_BASE + I2C_STATUS) & I2C_STATUS_BUSY) != 0u) {
    }
    mmio_write32(EDRV32_I2C0_BASE + I2C_IRQ_STAT, I2C_IRQ_DONE);
    mmio_write32(EDRV32_I2C0_BASE + I2C_CMD, command);
    while ((mmio_read32(EDRV32_I2C0_BASE + I2C_IRQ_STAT) & I2C_IRQ_DONE) == 0u) {
    }
    if ((command & I2C_CMD_READ) == 0u &&
        (mmio_read32(EDRV32_I2C0_BASE + I2C_STATUS) & I2C_STATUS_NACK) != 0u) {
        return -1;
    }
    return 0;
}

uint8_t i2c_read_data(void)
{
    return (uint8_t)mmio_read32(EDRV32_I2C0_BASE + I2C_RXDATA);
}

static int sccb_address(uint8_t device, uint16_t reg)
{
    if (i2c_command(I2C_CMD_START | ((uint32_t)device << 1)) != 0) {
        return -1;
    }
    if (i2c_command(reg >> 8) != 0) {
        return -1;
    }
    return i2c_command(reg & I2C_CMD_DATA_MASK);
}

int i2c_sccb_write(uint8_t device, uint16_t reg, uint8_t value)
{
    if (sccb_address(device, reg) != 0) {
        return -1;
    }
    return i2c_command(I2C_CMD_STOP | value);
}

int i2c_sccb_read(uint8_t device, uint16_t reg, uint8_t *value)
{
    if (sccb_address(device, reg) != 0) {
        return -1;
    }
    if (i2c_command(I2C_CMD_START | ((uint32_t)device << 1) | 1u) != 0) {
        return -1;
    }
    if (i2c_command(I2C_CMD_READ | I2C_CMD_NACK | I2C_CMD_STOP) != 0) {
        return -1;
    }
    *value = i2c_read_data();
    return 0;
}
