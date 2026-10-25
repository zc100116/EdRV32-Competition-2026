/* File: sc04.c
 * Spec: sys-subsys-testplan 3.6 SC-04
 * Description: Minimal SRAM application reached by the ROM bootloader.
 * Clock domain: clk_sys.
 */
#include "sc.h"

int main(void)
{
    sysctrl_write(SYSCTRL_SCRATCH1, 0x53430004u);
    sc_finish(0u);
}
