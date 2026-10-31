/* File: app.c
 * Spec: edrv32-soc-spec 7.5(3a); T-BIOS2 acceptance.
 * Description: Check ELF initialized data, BSS and the SRAM segment after automatic DDR entry.
 * Clock domain: clk_sys.
 */
#include "sysctrl.h"
#include "uart.h"
static volatile uint32_t initialized = 0x12345678u;
static volatile uint32_t zeroed;
int main(void)
{
    uint32_t code = initialized != 0x12345678u || zeroed != 0u ||
                    *(volatile uint32_t *)EDRV32_SRAM_BASE != 0xdecaf123u;
    uart_puts(code ? "BIOS application FAIL\r\n" : "BIOS application PASS\r\n");
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    for (;;) {
    }
}
