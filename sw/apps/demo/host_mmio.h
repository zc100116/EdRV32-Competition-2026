/* File: host_mmio.h
 * Spec: Task B3-12 host acceptance; SoC 7.3.
 * Description: Replace only MMIO access for software event-sequence tests.
 * Clock domain: none (host).
 */
#ifndef EDRV32_DEMO_HOST_MMIO_H
#define EDRV32_DEMO_HOST_MMIO_H
#define EDRV32_MMIO_H
#include <stdint.h>
#include "soc_map.h"
uint32_t mmio_read32(uintptr_t address);
void mmio_write32(uintptr_t address, uint32_t value);
#endif
