/* File: download.c
 * Spec: board-plan B1-5; sw/boot/README.md UART protocol.
 * Description: Small SRAM download payload; report through real UART and SIM_EXIT.
 * Clock domain: clk_sys.
 */
#include "sysctrl.h"
#include "uart.h"

int main(void)
{
    /* The bootloader has already configured UART at 115200 8N1. */
    uart_puts("B1 UART application PASS\r\n");
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, 0u);
    for (;;) {
    }
}
