/* File: sysctrl.h
 * Spec: sys-subsys-spec 4.6
 * Description: SYSCTRL register offsets, fields and software interface.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_SYSCTRL_H
#define EDRV32_SYSCTRL_H
#include "mmio.h"

#define SYSCTRL_ID 0x000u
#define SYSCTRL_CHIP_ID 0x004u
#define SYSCTRL_CLK_SYS_HZ 0x008u
#define SYSCTRL_STATUS 0x00cu
#define SYSCTRL_SCRATCH0 0x010u
#define SYSCTRL_SCRATCH1 0x014u
#define SYSCTRL_SOFT_RESET 0x018u
#define SYSCTRL_SIM_EXIT 0x01cu

#define SYSCTRL_STATUS_MEM_READY 0x1u
#define SYSCTRL_RESET_MEDIA 0x1u
#define SYSCTRL_RESET_SOC 0x2u

static inline uint32_t sysctrl_read(uint32_t offset)
{
    return mmio_read32(EDRV32_SYSCTRL_BASE + offset);
}

static inline void sysctrl_write(uint32_t offset, uint32_t value)
{
    mmio_write32(EDRV32_SYSCTRL_BASE + offset, value);
}
#endif
