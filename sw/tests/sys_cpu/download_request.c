/* File: download_request.c
 * Spec: sys-subsys-testplan 3.6 SC-04; edrv32-soc-spec 7.5.
 * Description: Request a UART download through persistent scratch and a SoC reset.
 * Clock domain: clk_sys.
 */
#include "edrv32.h"
#include "sysctrl.h"

int main(void)
{
    sysctrl_write(SYSCTRL_SCRATCH0, 0x55415254u);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SOFT_RESET, 2u);
    for (;;) {
        __asm__ volatile ("wfi");
    }
}
