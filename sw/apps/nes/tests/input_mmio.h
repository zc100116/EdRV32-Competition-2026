/* File: input_mmio.h
 * Spec: sys-subsys 2.6; Task T-NESKEY host regression.
 * Description: Replace MMIO accesses with the finite UART FIFO model.
 * Clock domain: deterministic host microseconds.
 */
#ifndef EDRV32_MMIO_H
#define EDRV32_MMIO_H
#include <stdint.h>
#include "soc_map.h"
uint32_t mmio_read32(uintptr_t address);
void mmio_write32(uintptr_t address, uint32_t value);
#endif
