/* File: host.c
 * Spec: sys-subsys-testplan 3.6 SC-07; CLAUDE.md 9.2.
 * Description: Use the real UART and SYSCTRL for benchmark console and completion.
 *              Configure HPM3--10 exactly as in the C-I3 B2 software host.
 * Clock domain: clk_sys.
 */
#include "edrv32.h"
#include "sysctrl.h"
#include "uart.h"

void edrv32_putchar(char value)
{
    uart_putc((uint8_t)value);
}

_Noreturn void edrv32_exit(int status)
{
    uart_drain();
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, (uint32_t)status);
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

int __real_main(void);
int __wrap_main(void)
{
    __asm__ volatile (
        "csrwi 0x323, 1\ncsrwi 0x324, 2\ncsrwi 0x325, 3\ncsrwi 0x326, 4\n"
        "csrwi 0x327, 5\ncsrwi 0x328, 6\ncsrwi 0x329, 7\ncsrwi 0x32a, 8"
        ::: "memory");
    return __real_main();
}
