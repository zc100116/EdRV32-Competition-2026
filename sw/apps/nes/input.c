/* File: input.c
 * Spec: sys-subsys 2.5/2.6; Task T-NESKEY.
 * Description: Drain UART on RX threshold interrupts during NES emulation.
 * Clock domain: clk_sys.
 */
#include <stdio.h>
#include <stdlib.h>
#include "input.h"
#include "plic.h"

uint32_t nes_input_lock(void)
{
    uint32_t state;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(state) :: "memory");
    return state;
}

void nes_input_unlock(uint32_t state)
{
    if (state & 8u)
        __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}

static void __attribute__((interrupt("machine"), aligned(4))) nes_interrupt(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause == 0x8000000bu) {
        unsigned source = plic_claim();
        if (source == EDRV32_PLIC_SOURCE_UART0)
            nes_uart_receive();
        if (source != EDRV32_PLIC_SOURCE_NONE)
            plic_complete(source);
    } else {
        uint32_t pc;
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        fprintf(stderr, "NES CPU mcause=0x%08lx mepc=0x%08lx\n",
                (unsigned long)cause, (unsigned long)pc);
        exit(1);
    }
}

void nes_input_init(void)
{
    uintptr_t handler = (uintptr_t)nes_interrupt;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    nes_uart_start();
    __asm__ volatile ("csrw mie, %0" :: "r"(1u << 11) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}
