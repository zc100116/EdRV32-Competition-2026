/* File: main.c
 * Spec: SoC 3.5, 7.5; Task B3-4b.
 * Description: DDR application with CLINT profiling and interrupt-driven UART input.
 * Clock domain: clk_sys; Spike uses retired instructions as its profiling timebase.
 */
#include <stdio.h>
#include "nes_port.h"
#if NES_DISPLAY
#include "display.h"
#endif
#ifndef NES_SPIKE
#include "clint.h"
#include "sysctrl.h"
#include "uart.h"
#include "gpio.h"
#include "plic.h"
#include "input.h"
#include "eth.h"
#include "eth_monitor.h"
#include "virtual_input.h"
#include <stdlib.h>
static uint32_t clock_hz;
static volatile uint64_t release_at[8];
#else
#include "edrv32.h"
#endif

extern unsigned char nes_rom_slot[];

char *osd_getromdata(void) { return (char *)nes_rom_slot; }

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

#ifndef NES_SPIKE
/* sys-subsys 2.6: service RX independently of the emulator/display frame rate. */
static void nes_character(int character)
{
    const char keys[8] = {'j', 'k', 'u', 'i', 'w', 's', 'a', 'd'};
    uint64_t now = clint_time();
    for (unsigned i = 0; i < 8; ++i)
        if (character == (uint8_t)keys[i])
            release_at[i] = now + clock_hz / 10;
}

void nes_uart_start(void)
{
    plic_set_threshold(0);
    plic_set_enable(0);
    virtual_input_uart_start(nes_character);
}
#endif

unsigned nes_buttons(void)
{
#ifdef NES_SPIKE
    return 0;
#else
    struct engine_event event = engine_poll(ENGINE_ETH);
    if (event.error || (event.irq & EDRV32_ETH_IRQ_STAT_ERROR_MASK)) {
        fprintf(stderr, "NES ETH ERR_CODE=%lu\n", (unsigned long)event.error);
        exit(1);
    }
    if (event.irq & EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK) {
        uint32_t interrupt_state = virtual_input_lock();
        virtual_input_network((const volatile uint8_t *)(uintptr_t)
            (EDRV32_DDR_UNCACHED_BASE + VIRTUAL_INPUT_BASE));
        virtual_input_unlock(interrupt_state);
    }
    if (event.irq & EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK) {
        eth_window_configure(3, 0x0a000000u, 0x10000u);
        printf("ETH peer IP: 0x%08lx\nETH peer port: %lu\n",
            (unsigned long)mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_IP_OFFSET),
            (unsigned long)mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET));
    }
    engine_irq_clear(ENGINE_ETH, event.irq);
    uint32_t interrupt_state = virtual_input_lock();
    uint64_t now = clint_time();
    unsigned buttons = 0;
    for (unsigned i = 0; i < 8; ++i)
        if (now < release_at[i])
            buttons |= 1u << i;
    uint16_t virtual_keys = virtual_input_get().keys;
    virtual_input_unlock(interrupt_state);
    unsigned physical = (unsigned)~gpio_read();
    if (physical & 1) buttons |= 1u << 6;
    if (physical & 2) buttons |= 1u << 7;
    if (physical & 4) buttons |= 1u << 0;
    if (physical & 8) buttons |= 1u << 3;
    return nes_merge_virtual(buttons, virtual_keys);
#endif
}

void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame)
{
#if NES_DISPLAY
    nes_display_frame(pixels, palette);
#else
    (void)pixels;
    (void)palette;
#endif
    (void)frame;
}

int main(void)
{
#ifndef NES_SPIKE
    (void)virtual_input_lock();
    uart_init();
    clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    nes_input_init();
    eth_monitor_local_init(clock_hz);
    eth_window_configure(3, 0x0a000000u, 0x10000u);
    eth_window_configure(VIRTUAL_INPUT_WINDOW, VIRTUAL_INPUT_BASE, VIRTUAL_INPUT_BYTES);
    engine_control(ENGINE_ETH, EDRV32_ETH_CTRL_ENABLE_MASK);
#endif
    setvbuf(stdout, NULL, _IONBF, 0);
#if NES_DISPLAY
    nes_display_init();
#endif
    nes_frame_limit = NES_FRAMES;
    nes_skip_render = NES_SKIP;
    nes_run();
    return 0;
}
