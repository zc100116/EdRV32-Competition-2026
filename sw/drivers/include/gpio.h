/* File: gpio.h
 * Spec: sys-subsys-spec 4.4
 * Description: GPIO register offsets, fields and software interface.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_GPIO_H
#define EDRV32_GPIO_H
#include "mmio.h"

#define GPIO_ID 0x000u
#define GPIO_OUT 0x004u
#define GPIO_OE 0x008u
#define GPIO_IN 0x00cu
#define GPIO_RISE_EN 0x010u
#define GPIO_FALL_EN 0x014u
#define GPIO_IRQ_STAT 0x018u
#define GPIO_DEBOUNCE 0x01cu

#define GPIO_PIN_MASK 0xffffu
#define GPIO_DEBOUNCE_MASK 0xffffffu

void gpio_write(uint16_t value);
void gpio_set_output_enable(uint16_t mask);
uint16_t gpio_read(void);
void gpio_set_edges(uint16_t rising, uint16_t falling);
uint16_t gpio_irq_status(void);
void gpio_irq_clear(uint16_t mask);
void gpio_set_debounce(uint32_t cycles);
#endif
