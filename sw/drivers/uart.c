/* File: uart.c
 * Spec: sys-subsys-spec 2.6, 4.3
 * Description: Polling UART transmit/receive and baud selection.
 * Clock domain: clk_sys.
 */
#include "uart.h"

void uart_init(void)
{
    mmio_write32(EDRV32_UART0_BASE + UART_CTRL, UART_CTRL_TX_EN | UART_CTRL_RX_EN);
}

void uart_set_baud(uint32_t clock_hz, uint32_t baud)
{
    uint32_t divisor = (uint32_t)(((uint64_t)clock_hz * 16u + baud / 2u) / baud);
    mmio_write32(EDRV32_UART0_BASE + UART_BAUD_DIV, divisor);
}

void uart_putc(uint8_t value)
{
    while ((mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_TX_FULL) != 0u) {
    }
    mmio_write32(EDRV32_UART0_BASE + UART_TXDATA, value);
}

uint8_t uart_getc(void)
{
    uint32_t data;
    do {
        data = mmio_read32(EDRV32_UART0_BASE + UART_RXDATA);
    } while ((data & UART_RXDATA_VALID) == 0u);
    return (uint8_t)data;
}

void uart_puts(const char *text)
{
    while (*text != '\0') {
        uart_putc((uint8_t)*text++);
    }
}

void uart_drain(void)
{
    while ((mmio_read32(EDRV32_UART0_BASE + UART_STATUS) &
            (UART_STATUS_TX_EMPTY | UART_STATUS_TX_BUSY)) != UART_STATUS_TX_EMPTY) {
    }
}
