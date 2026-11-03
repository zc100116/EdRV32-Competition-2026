/* File: virtual_input_uart.c
 * Spec: sys-subsys 2.5/2.6; Tasks T-NESKEY/T-S3IN.
 * Description: Drain and parse UART independently of application frame timing.
 * Clock domain: clk_sys.
 */
#include "virtual_input.h"
#include "virtual_input_uart.h"
#include "uart.h"
#include "plic.h"

static void (*legacy_character)(int);
static void (*raw_receive)(unsigned);
void virtual_input_uart_set_raw(void (*receive)(unsigned)) { raw_receive=receive; }

void virtual_input_uart_start(void (*character)(int))
{
    legacy_character = character;
    plic_set_priority(EDRV32_PLIC_SOURCE_UART0, 1);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                    (1u << EDRV32_PLIC_SOURCE_UART0));
    mmio_write32(EDRV32_UART0_BASE + UART_RX_THRESH, 1);
    mmio_write32(EDRV32_UART0_BASE + UART_IRQ_EN, UART_IRQ_RX_THRESH);
}

void virtual_input_uart_receive(void)
{
    unsigned budget=32;
    while (budget-- && !(mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_RX_EMPTY)) {
        unsigned byte=uart_getc();
        if(raw_receive) { raw_receive(byte); continue; }
        int character = virtual_input_serial((uint8_t)byte);
        if (character >= 0)
            legacy_character(character);
    }
}
