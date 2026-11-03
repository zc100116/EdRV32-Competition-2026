/* overlay.h — showcase 4.6.5; NES-only software L1 display, clk_sys. */
#ifndef SHOWCASE_OVERLAY_H
#define SHOWCASE_OVERLAY_H
#include <stdint.h>
void board_overlay_enter(void);
void board_overlay_step(void);
void board_overlay_irq(uint32_t irq);
void board_overlay_exit(void);
uint64_t board_overlay_ticks(void);
unsigned board_overlay_max_us(void);
#endif
