/* ============================================================================
 * File        : edrv32_uart.h
 * Author      : Edward ZC
 * Description : Polling UART0 HAL used by board diagnostics and benchmarks.
 * Notes       : Divider is system_clock/baud - 1.  API is timeout bounded.
 * ========================================================================== */
#ifndef EDRV32_UART_H
#define EDRV32_UART_H

#define EDRV32_UART_DIVISOR(clock_hz, baud) \
    ((((clock_hz) + ((baud) / 2u)) / (baud)) - 1u)

#define EDRV32_UART_OK       0
#define EDRV32_UART_TIMEOUT -1
#define EDRV32_UART_ERROR   -2

void edrv32_uart_init(unsigned int divider);
int edrv32_uart_putc_timeout(char value, unsigned int timeout_cycles);
int edrv32_uart_getc_timeout(char *value, unsigned int timeout_cycles);
int edrv32_uart_flush_timeout(unsigned int timeout_cycles);
void edrv32_uart_clear_rx(void);
void edrv32_uart_putc(char value);
void edrv32_uart_puts(const char *text);
void edrv32_uart_put_hex32(unsigned int value);

#endif /* EDRV32_UART_H */
