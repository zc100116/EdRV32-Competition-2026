/* host_mmio.h — npu-spec 4, SoC 7.4; mock MMIO boundary for driver ordering.
 * Clock domain: host CPU.
 */
#ifndef PP_HOST_MMIO_H
#define PP_HOST_MMIO_H
#define EDRV32_MMIO_H
#include <stdint.h>
#include "soc_map.h"
uint32_t mmio_read32(uintptr_t address);
void mmio_write32(uintptr_t address, uint32_t value);
#endif
