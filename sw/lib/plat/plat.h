/* File: plat.h
 * Spec: PC design 4.4; S-0b platform interface.
 * Description: Game clock, controller, logging and DMA-visible allocation.
 * Clock domain: CPU or host main loop.
 */
#ifndef EDRV32_PLAT_H
#define EDRV32_PLAT_H
#include <stdint.h>
#include <stddef.h>
enum plat_key {
    PLAT_UP = 1u << 0, PLAT_DOWN = 1u << 1, PLAT_LEFT = 1u << 2,
    PLAT_RIGHT = 1u << 3, PLAT_A = 1u << 4, PLAT_B = 1u << 5,
    PLAT_SELECT = 1u << 6, PLAT_START = 1u << 7
};
void plat_init(void);
void plat_wait_vsync(void);
uint32_t plat_keys(void);
uint32_t plat_millis(void);
int plat_printf(const char *format, ...);
void *plat_dma_alloc(size_t bytes, size_t alignment);
typedef void (*plat_irq_handler)(void *context);
void plat_irq_register(unsigned source, plat_irq_handler handler, void *context);
void plat_irq_dispatch(void);
#endif
