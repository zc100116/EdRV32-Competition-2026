/* File: mmio.h
 * Spec: sys-subsys-spec 4; edrv32-soc-spec 6.3
 * Description: 32-bit register accesses and CPU-to-DDR physical address conversion.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_MMIO_H
#define EDRV32_MMIO_H
#include <stdint.h>
#include "soc_map.h"

static inline uint32_t mmio_read32(uintptr_t address)
{
    return *(volatile uint32_t *)address;
}

static inline void mmio_write32(uintptr_t address, uint32_t value)
{
    *(volatile uint32_t *)address = value;
}

/* visual SoC 6.3: both CPU DDR aliases map to physical byte offsets. */
static inline uint32_t ddr_physical(const void *address)
{
    uintptr_t cpu = (uintptr_t)address;
    return (uint32_t)(cpu - (cpu >= EDRV32_DDR_UNCACHED_BASE ?
                            EDRV32_DDR_UNCACHED_BASE : EDRV32_DDR_BASE));
}
#endif
