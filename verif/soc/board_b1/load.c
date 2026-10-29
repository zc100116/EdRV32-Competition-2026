/* File: load.c
 * Spec: edrv32-soc-spec 7.5(3a), 7.5(3b); Task B1-10.
 * Description: Two file-backed ELF segments, restored data/BSS and one UART success line.
 * Clock domain: clk_sys.
 */
#include "sysctrl.h"
#include "uart.h"

static volatile uint32_t initialized = 0x12345678u;
static volatile uint32_t zeroed;

int main(void)
{
    if (initialized != 0x12345678u || zeroed != 0u) {
        sysctrl_write(SYSCTRL_SIM_EXIT, 1u);
        for (;;) {
        }
    }
    uart_puts("B1 ELF application PASS\r\n");
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, 0u);
    for (;;) {
    }
}
