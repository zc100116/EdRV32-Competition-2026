/* File: main.c
 * Spec: gpu-soc-testplan ST-08; gpu-soc-spec 8.1; CLAUDE.md 9.2.
 * Description: Check the GPU chip identity after the real Boot ROM Run command.
 *              Print the result through UART and terminate through SYSCTRL SIM_EXIT.
 * Clock domain: clk_sys.
 */
#include "sysctrl.h"
#include "uart.h"

int main(void)
{
    uint32_t chip = sysctrl_read(SYSCTRL_CHIP_ID);
    uint32_t code = chip != 0xed320002u;
    uart_puts(code ? "GPU CHIP_ID FAIL\r\n" : "GPU CHIP_ID ed320002 PASS\r\n");
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    for (;;) __asm__ volatile ("wfi");
}
