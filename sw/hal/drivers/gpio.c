/* ============================================================================
 * File        : gpio.c
 * Author      : Edward ZC
 * Description : GPIO0 polling driver.
 * Notes       : Register definitions follow edrv32_periph_abi.vh.
 * ========================================================================== */
#include "edrv32_gpio.h"
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"

#define GPIO_DIR_OFFSET     0x00u
#define GPIO_OUT_OFFSET     0x04u
#define GPIO_IN_OFFSET      0x08u
#define GPIO_OUT_SET_OFFSET 0x0cu
#define GPIO_OUT_CLR_OFFSET 0x10u

void edrv32_gpio_set_direction(unsigned int output_mask)
{
    edrv32_mmio_write32(SOC_GPIO0_BASE + GPIO_DIR_OFFSET, output_mask);
}

void edrv32_gpio_write(unsigned int value)
{
    edrv32_mmio_write32(SOC_GPIO0_BASE + GPIO_OUT_OFFSET, value);
}

void edrv32_gpio_set(unsigned int mask)
{
    edrv32_mmio_write32(SOC_GPIO0_BASE + GPIO_OUT_SET_OFFSET, mask);
}

void edrv32_gpio_clear(unsigned int mask)
{
    edrv32_mmio_write32(SOC_GPIO0_BASE + GPIO_OUT_CLR_OFFSET, mask);
}

unsigned int edrv32_gpio_read(void)
{
    return edrv32_mmio_read32(SOC_GPIO0_BASE + GPIO_IN_OFFSET);
}

unsigned int edrv32_gpio_read_output(void)
{
    return edrv32_mmio_read32(SOC_GPIO0_BASE + GPIO_OUT_OFFSET);
}

unsigned int edrv32_gpio_read_direction(void)
{
    return edrv32_mmio_read32(SOC_GPIO0_BASE + GPIO_DIR_OFFSET);
}
