/* File: mmio.h
 * Spec: PC design 4.1; gpu-soc-spec 6.1.
 * Description: Host replacement for the board MMIO and DDR address conversion.
 * Clock domain: host main loop.
 */
#ifndef EDRV32_MMIO_H
#define EDRV32_MMIO_H
#include <stdint.h>
#include "gpu_soc_map.h"
uint32_t mmio_read32(uintptr_t address);
void mmio_write32(uintptr_t address, uint32_t value);
uint32_t ddr_physical(const void *address);
#endif
