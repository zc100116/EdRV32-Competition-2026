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
/* Ember Isles tech 3; separate from the legacy controller bitmap above. */
enum plat_game_key {
    PLAT_KEY_W = 1u << 0, PLAT_KEY_A = 1u << 1, PLAT_KEY_S = 1u << 2,
    PLAT_KEY_D = 1u << 3, PLAT_KEY_J = 1u << 4, PLAT_KEY_K = 1u << 5,
    PLAT_KEY_L = 1u << 6, PLAT_KEY_U = 1u << 7, PLAT_KEY_Q = 1u << 8,
    PLAT_KEY_F = 1u << 9, PLAT_KEY_SPACE = 1u << 10,
    PLAT_KEY_ESC = 1u << 11, PLAT_KEY_ENTER = 1u << 12
};
struct plat_pointer_state {
    int16_t x;
    int16_t y;
    uint8_t buttons; /* bits 0/1/2: left/right/middle; 640 x 360 menu coordinates */
};
void plat_init(void);
void plat_wait_vsync(void);
uint32_t plat_keys(void);
uint32_t plat_game_keys(void);
struct plat_pointer_state plat_pointer(void);
uint32_t plat_millis(void);
int plat_printf(const char *format, ...);
void *plat_dma_alloc(size_t bytes, size_t alignment);
typedef void (*plat_irq_handler)(void *context);
void plat_irq_register(unsigned source, plat_irq_handler handler, void *context);
void plat_irq_dispatch(void);
#endif
