/* File: fake_mmio.h
 * Spec: Task B3-4b step 2; SoC 7.3/7.4; disp-spec 5.3.
 * Description: Replace only register transport in the Linux ownership test.
 * Clock domain: host test events.
 */
#ifndef EDRV32_MMIO_H
#define EDRV32_MMIO_H
#include <stdint.h>
#include "soc_map.h"
uint32_t mmio_read32(uintptr_t address);
void mmio_write32(uintptr_t address, uint32_t value);
#endif
