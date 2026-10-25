/* ============================================================================
 * File        : uart.c
 * Author      : Edward ZC
 * Description : Polling UART0 driver with FIFO flow control.
 * Notes       : Uses 8N1 and no hardware flow control.
 * ========================================================================== */
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"
#include "edrv32_uart.h"

#define UART_TXDATA_OFFSET 0x00u
#define UART_RXDATA_OFFSET 0x04u
#define UART_STATUS_OFFSET 0x08u
#define UART_CTRL_OFFSET   0x0cu
#define UART_CLKDIV_OFFSET 0x10u
#define UART_FORMAT_OFFSET 0x14u
#define UART_IP_OFFSET     0x18u

#define UART_STATUS_TX_EMPTY (1u << 0)
#define UART_STATUS_TX_FULL  (1u << 1)
#define UART_STATUS_RX_EMPTY (1u << 2)
#define UART_STATUS_TX_BUSY  (1u << 4)
#define UART_STATUS_ERROR    (7u << 5)

#define UART_CTRL_ENABLE      (1u << 0)
#define UART_CTRL_CLEAR_TX    (1u << 2)
#define UART_CTRL_CLEAR_RX    (1u << 3)
#define UART_IP_ERROR         (1u << 2)
#define UART_FORMAT_8N1       3u

#define UART_DEFAULT_TIMEOUT 10000000u

static unsigned int uart_ctrl_shadow = UART_CTRL_ENABLE;

static unsigned int uart_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_UART0_BASE + offset);
}

static void uart_write(unsigned int offset, unsigned int value)
{
    edrv32_mmio_write32(SOC_UART0_BASE + offset, value);
}

void edrv32_uart_init(unsigned int divider)
{
    uart_write(UART_CTRL_OFFSET, 0u);
    uart_write(UART_CLKDIV_OFFSET, divider & 0xffffu);
    uart_write(UART_FORMAT_OFFSET, UART_FORMAT_8N1);
    uart_ctrl_shadow = UART_CTRL_ENABLE;
    uart_write(UART_CTRL_OFFSET, uart_ctrl_shadow |
                                  UART_CTRL_CLEAR_TX |
                                  UART_CTRL_CLEAR_RX);
    uart_write(UART_IP_OFFSET, UART_IP_ERROR);
}

void edrv32_uart_clear_rx(void)
{
    // FIFO clear bits are self-clearing.  Clear the queued bytes first, then
    // acknowledge the sticky frame/parity/overrun summary through IP.W1C.
    uart_write(UART_CTRL_OFFSET, uart_ctrl_shadow | UART_CTRL_CLEAR_RX);
    uart_write(UART_IP_OFFSET, UART_IP_ERROR);
}

int edrv32_uart_putc_timeout(char value, unsigned int timeout_cycles)
{
    while (timeout_cycles != 0u) {
        if ((uart_read(UART_STATUS_OFFSET) & UART_STATUS_TX_FULL) == 0u) {
            uart_write(UART_TXDATA_OFFSET, (unsigned int)(unsigned char)value);
            return EDRV32_UART_OK;
        }
        timeout_cycles--;
    }
    return EDRV32_UART_TIMEOUT;
}

int edrv32_uart_getc_timeout(char *value, unsigned int timeout_cycles)
{
    unsigned int status;

    if (value == (char *)0)
        return EDRV32_UART_ERROR;

    while (timeout_cycles != 0u) {
        status = uart_read(UART_STATUS_OFFSET);
        if ((status & UART_STATUS_ERROR) != 0u) {
            edrv32_uart_clear_rx();
            return EDRV32_UART_ERROR;
        }
        if ((status & UART_STATUS_RX_EMPTY) == 0u) {
            *value = (char)(uart_read(UART_RXDATA_OFFSET) & 0xffu);
            return EDRV32_UART_OK;
        }
        timeout_cycles--;
    }
    return EDRV32_UART_TIMEOUT;
}

int edrv32_uart_flush_timeout(unsigned int timeout_cycles)
{
    unsigned int status;

    while (timeout_cycles != 0u) {
        status = uart_read(UART_STATUS_OFFSET);
        if ((status & (UART_STATUS_TX_EMPTY | UART_STATUS_TX_BUSY)) ==
            UART_STATUS_TX_EMPTY)
            return EDRV32_UART_OK;
        timeout_cycles--;
    }
    return EDRV32_UART_TIMEOUT;
}

void edrv32_uart_putc(char value)
{
    (void)edrv32_uart_putc_timeout(value, UART_DEFAULT_TIMEOUT);
}

void edrv32_uart_puts(const char *text)
{
    while (*text != '\0') {
        if (*text == '\n')
            edrv32_uart_putc('\r');
        edrv32_uart_putc(*text);
        text++;
    }
}

void edrv32_uart_put_hex32(unsigned int value)
{
    static const char hex[] = "0123456789ABCDEF";
    int shift;

    edrv32_uart_puts("0x");
    for (shift = 28; shift >= 0; shift -= 4)
        edrv32_uart_putc(hex[(value >> shift) & 0xfu]);
}
