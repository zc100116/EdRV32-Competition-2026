/* ============================================================================
 * File        : edrv32_gpio.h
 * Author      : Edward ZC
 * Description : GPIO0 polling HAL.
 * Notes       : The Competition SoC exposes the low 16 GPIO bits at top level.
 * ========================================================================== */
#ifndef EDRV32_GPIO_H
#define EDRV32_GPIO_H

void edrv32_gpio_set_direction(unsigned int output_mask);
void edrv32_gpio_write(unsigned int value);
void edrv32_gpio_set(unsigned int mask);
void edrv32_gpio_clear(unsigned int mask);
unsigned int edrv32_gpio_read(void);
unsigned int edrv32_gpio_read_output(void);
unsigned int edrv32_gpio_read_direction(void);

#endif /* EDRV32_GPIO_H */
