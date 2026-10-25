/* File: clint.c
 * Spec: sys-subsys-spec 2.4, 4.1
 * Description: RV32 stable time reads and compare updates without a transient low deadline.
 * Clock domain: clk_sys.
 */
#include "clint.h"

uint64_t clint_time(void)
{
    uint32_t high;
    uint32_t low;
    uint32_t again;
    do {
        high = mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIME_HI);
        low = mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIME_LO);
        again = mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIME_HI);
    } while (high != again);
    return ((uint64_t)high << 32) | low;
}

void clint_set_compare(uint64_t value)
{
    mmio_write32(EDRV32_CLINT_BASE + CLINT_MTIMECMP_LO, UINT32_MAX);
    mmio_write32(EDRV32_CLINT_BASE + CLINT_MTIMECMP_HI, (uint32_t)(value >> 32));
    mmio_write32(EDRV32_CLINT_BASE + CLINT_MTIMECMP_LO, (uint32_t)value);
}

void clint_set_software_irq(unsigned int pending)
{
    mmio_write32(EDRV32_CLINT_BASE + CLINT_MSIP, pending);
}
