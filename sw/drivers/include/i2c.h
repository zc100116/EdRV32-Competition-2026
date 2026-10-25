/* File: i2c.h
 * Spec: sys-subsys-spec 4.5
 * Description: I2C register offsets, fields and software interface.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_I2C_H
#define EDRV32_I2C_H
#include "mmio.h"

#define I2C_ID 0x000u
#define I2C_CTRL 0x004u
#define I2C_STATUS 0x008u
#define I2C_IRQ_EN 0x00cu
#define I2C_IRQ_STAT 0x010u
#define I2C_CLK_DIV 0x014u
#define I2C_CMD 0x018u
#define I2C_RXDATA 0x01cu

#define I2C_CTRL_EN 0x1u
#define I2C_CTRL_PORT_SEL 0x2u
#define I2C_STATUS_BUSY 0x1u
#define I2C_STATUS_NACK 0x2u
#define I2C_STATUS_BUS_HELD 0x4u
#define I2C_IRQ_DONE 0x1u
#define I2C_CLK_DIV_MASK 0xffffu
#define I2C_CMD_DATA_MASK 0xffu
#define I2C_CMD_START 0x100u
#define I2C_CMD_STOP 0x200u
#define I2C_CMD_READ 0x400u
#define I2C_CMD_NACK 0x800u
#define I2C_RXDATA_MASK 0xffu

void i2c_init(unsigned int port, uint32_t clock_hz, uint32_t scl_hz);
int i2c_command(uint32_t command);
uint8_t i2c_read_data(void);
int i2c_sccb_write(uint8_t device, uint16_t reg, uint8_t value);
int i2c_sccb_read(uint8_t device, uint16_t reg, uint8_t *value);
#endif
