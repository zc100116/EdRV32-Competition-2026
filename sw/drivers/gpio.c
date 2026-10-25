/* File: gpio.c
 * Spec: sys-subsys-spec 2.7, 4.4
 * Description: GPIO direction, levels, debounce and edge interrupt access.
 * Clock domain: clk_sys.
 */
#include "gpio.h"

void gpio_write(uint16_t value)
{
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_OUT, value);
}

void gpio_set_output_enable(uint16_t mask)
{
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_OE, mask);
}

uint16_t gpio_read(void)
{
    return (uint16_t)mmio_read32(EDRV32_GPIO0_BASE + GPIO_IN);
}

void gpio_set_edges(uint16_t rising, uint16_t falling)
{
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_RISE_EN, rising);
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_FALL_EN, falling);
}

uint16_t gpio_irq_status(void)
{
    return (uint16_t)mmio_read32(EDRV32_GPIO0_BASE + GPIO_IRQ_STAT);
}

void gpio_irq_clear(uint16_t mask)
{
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_IRQ_STAT, mask);
}

void gpio_set_debounce(uint32_t cycles)
{
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_DEBOUNCE, cycles);
}
