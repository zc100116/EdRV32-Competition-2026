/* File: virtual_input_irq.c
 * Spec: sys-subsys 2.5; Tasks T-NESKEY/T-S3IN.
 * Description: Preserve machine interrupt enable across input snapshots.
 * Clock domain: clk_sys.
 */
#include "virtual_input_uart.h"

uint32_t virtual_input_lock(void)
{
    uint32_t state;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(state) :: "memory");
    return state;
}

void virtual_input_unlock(uint32_t state)
{
    if (state & 8u)
        __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}
