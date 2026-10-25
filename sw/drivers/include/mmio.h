/* File: mmio.h
 * Spec: sys-subsys-spec 4
 * Description: 32-bit accesses to generated SoC base addresses.
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
#endif
