/* File: platform.h
 * Design: 2026-11-02-showcase-software 4.1/4.2/4.4.
 * Description: Shared IRQ owner and NES/application event routing.
 * Clock domain: clk_sys; media interrupts originate in clk_mem.
 */
#ifndef SHOWCASE_PLATFORM_H
#define SHOWCASE_PLATFORM_H
#include <stdint.h>
#include "rnd.h"
#include "disp.h"
#include "virtual_input.h"
enum platform_event {
    PLATFORM_INPUT = 1u << 0,
    PLATFORM_RND = 1u << 1,
    PLATFORM_FRAME = 1u << 2,
    PLATFORM_SWITCH = 1u << 3,
    PLATFORM_SWITCH1 = 1u << 4
};
enum platform_key {
    PLATFORM_LEFT = 1u, PLATFORM_RIGHT = 2u,
    PLATFORM_ENTER = 4u, PLATFORM_BACK = 8u
};
void platform_init(void);
uint64_t platform_ticks(void);
uint32_t platform_clock_hz(void);
uint32_t platform_milliseconds(void);
uint32_t platform_hardware(void);
/* Returns PLATFORM_* bits (not VI_*); KEY4/virtual ESC => PLATFORM_BACK.
 * platform_virtual_input() returns the unmodified virtual VI_* controller state. */
uint32_t platform_keys(void);
/* Pressed edges latched for the current application step; use with PLATFORM_INPUT. */
uint32_t platform_pressed(void);
/* Latest input transport: 0 none, 1 UART, 2 ETH WIN2. */
unsigned platform_input_source(void);
struct virtual_input_state platform_virtual_input(void);
uint32_t platform_frames(void);
/* NES owns RND/DISP while GUI is paused; callbacks receive captured IRQ results.
 * NULL restores core GUI callbacks. Call from enter/step/exit, never in an IRQ.
 */
void platform_media_callbacks(rnd_callback rnd_callback,
                              engine_irq_callback disp_callback, void *context);
/* Nonblocking: after requesting stop, call from later steps until true,
 * then restore media callbacks and call app_gui_pause(0). */
int platform_display_idle(void);
void platform_puts(const char *text);
void platform_put_u32(uint32_t value);
void platform_put_hex(uint32_t value);
_Noreturn void platform_stop(void);
void *platform_uncached(void *storage);
#endif
