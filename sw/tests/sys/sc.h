/* File: sc.h
 * Spec: sys-subsys-spec 2.9, 4.6; sys-subsys-testplan 3.6
 * Description: SC completion through SIM_EXIT, with tohost available for Spike.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_SC_H
#define EDRV32_SC_H
#include "edrv32.h"
#include "sysctrl.h"

static inline _Noreturn void sc_finish(uint32_t code)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    edrv32_exit((int)code);
}
#endif
