/* ============================================================================
 * File        : main.c
 * Author      : Edward ZC
 * Description : First board test: UART TX/RX echo and LED pattern.
 * Notes       : Runs entirely from Boot ROM and on-chip SRAM; DDR is disabled.
 * ========================================================================== */
#include "edrv32_gpio.h"
#include "edrv32_uart.h"

#ifndef EDRV32_SOC_CLOCK_HZ
#define EDRV32_SOC_CLOCK_HZ 50000000u
#endif

#ifndef EDRV32_UART_BAUD
#define EDRV32_UART_BAUD 115200u
#endif

#ifndef EDRV32_BOARD_NAME
#define EDRV32_BOARD_NAME "MES50HP"
#endif

#define UART_WAIT_CYCLES 50000000u

int main(void)
{
    char value;

    edrv32_gpio_set_direction(0x00ffu);
    edrv32_gpio_write(0x00a5u);
    edrv32_uart_init(EDRV32_UART_DIVISOR(EDRV32_SOC_CLOCK_HZ,
                                         EDRV32_UART_BAUD));
    edrv32_uart_puts("\nEdRV32 " EDRV32_BOARD_NAME " UART smoke\n");
    edrv32_uart_puts("clock=");
    edrv32_uart_put_hex32(EDRV32_SOC_CLOCK_HZ);
    edrv32_uart_puts(" baud=");
    edrv32_uart_put_hex32(EDRV32_UART_BAUD);
    edrv32_uart_puts(" format=8N1\n");
    edrv32_uart_puts("LED=A5; type characters for echo\n");
    edrv32_uart_puts("EDRV32_UART_TX_PASS\n");

    for (;;) {
        if (edrv32_uart_getc_timeout(&value, UART_WAIT_CYCLES) ==
            EDRV32_UART_OK) {
            edrv32_uart_puts("RX=");
            edrv32_uart_put_hex32((unsigned int)(unsigned char)value);
            edrv32_uart_puts(" echo=");
            edrv32_uart_putc(value);
            edrv32_uart_puts("\nEDRV32_UART_RX_PASS\n");
        }
    }
}
