/* File: sc01.c
 * Spec: sys-subsys-testplan 3.6 SC-01
 * Description: Minimal SRAM application reached by the ROM bootloader.
 * Clock domain: clk_sys.
 */
#include "sc.h"

int main(void)
{
    sysctrl_write(SYSCTRL_SCRATCH1, 0x53430001u);
    sc_finish(0u);
}
