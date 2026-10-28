/* File: download.c
 * Spec: board-plan B1-5; sw/boot/README.md UART protocol.
 * Description: Print data/BSS initial values, modify both and persist them before reset.
 * Clock domain: clk_sys.
 */
#include "sysctrl.h"
#include "uart.h"
#include "cache.h"

static volatile uint32_t initialized = 7u;
static volatile uint32_t zeroed;

int main(void)
{
    /* The bootloader has already configured UART at 115200 8N1. */
    uart_puts("B1 data: ");
    uart_putc((uint8_t)('0' + initialized));
    uart_puts(" bss: ");
    uart_putc((uint8_t)('0' + zeroed));
    uart_puts("\r\n");
    initialized = 9u;
    zeroed = 3u;
    cache_clean_all();
    uart_puts("B1 UART application PASS\r\n");
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, 0u);
    for (;;) {
    }
}
