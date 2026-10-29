/* File: main.c
 * Spec: SoC 7.5 steps 1-3a; soc-testplan SC-01.
 * Description: SRAM boot/download payload terminates through SIM_EXIT.
 * Clock domain: clk_sys.
 */
#include "sysctrl.h"
int main(void)
{
    sysctrl_write(SYSCTRL_SIM_EXIT, 0u);
    for (;;) {
        __asm__ volatile ("wfi");
    }
}
