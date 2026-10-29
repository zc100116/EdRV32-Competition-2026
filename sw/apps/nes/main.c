/* File: main.c
 * Spec: SoC 3.5, 7.5; Task B3-4b.
 * Description: DDR application with CLINT profiling and 100 ms UART button pulses.
 * Clock domain: clk_sys; Spike uses retired instructions as its profiling timebase.
 */
#include <stdio.h>
#include "nes_port.h"
#ifndef NES_SPIKE
#include "clint.h"
#include "sysctrl.h"
#include "uart.h"
#include "gpio.h"
static uint32_t clock_hz;
static uint64_t release_at[8];
#else
#include "edrv32.h"
#endif

uint64_t nes_instructions(void)
{
#ifndef NES_SPIKE
    return 0;
#else
    uint32_t high, low, second;
    do {
        __asm__ volatile ("rdinstreth %0" : "=r"(high));
        __asm__ volatile ("rdinstret %0" : "=r"(low));
        __asm__ volatile ("rdinstreth %0" : "=r"(second));
    } while (high != second);
    return ((uint64_t)high << 32) | low;
#endif
}

uint64_t nes_ticks(void)
{
#ifdef NES_SPIKE
    return nes_instructions();
#else
    return clint_time();
#endif
}

uint64_t nes_tick_hz(void)
{
#ifdef NES_SPIKE
    return 100000000;
#else
    return clock_hz;
#endif
}

unsigned nes_buttons(void)
{
#ifdef NES_SPIKE
    return 0;
#else
    const char keys[8] = {'j', 'k', 'u', 'i', 'w', 's', 'a', 'd'};
    uint64_t now = clint_time();
    while (!(mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_RX_EMPTY)) {
        uint8_t character = uart_getc();
        for (unsigned i = 0; i < 8; ++i)
            if (character == (uint8_t)keys[i])
                release_at[i] = now + clock_hz / 10;
    }
    unsigned buttons = 0;
    for (unsigned i = 0; i < 8; ++i)
        if (now < release_at[i])
            buttons |= 1u << i;
    unsigned physical = (unsigned)~gpio_read();
    if (physical & 1) buttons |= 1u << 6;
    if (physical & 2) buttons |= 1u << 7;
    if (physical & 4) buttons |= 1u << 0;
    if (physical & 8) buttons |= 1u << 3;
    return buttons;
#endif
}

void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame)
{
    (void)pixels;
    (void)palette;
    (void)frame;
}

int main(void)
{
#ifndef NES_SPIKE
    uart_init();
    clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
#endif
    setvbuf(stdout, NULL, _IONBF, 0);
    nes_frame_limit = NES_FRAMES;
    nes_skip_render = NES_SKIP;
    nes_run();
    return 0;
}
