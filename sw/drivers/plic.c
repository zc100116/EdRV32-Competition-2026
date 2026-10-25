/* File: plic.c
 * Spec: sys-subsys-spec 2.5, 4.2
 * Description: Single M-context interrupt priority, enable, claim and completion.
 * Clock domain: clk_sys.
 */
#include "plic.h"

void plic_set_priority(unsigned int source, unsigned int priority)
{
    mmio_write32(EDRV32_PLIC_BASE + PLIC_PRIORITY + 4u * source, priority);
}

void plic_set_enable(uint32_t sources)
{
    mmio_write32(EDRV32_PLIC_BASE + PLIC_ENABLE, sources);
}

void plic_set_threshold(unsigned int threshold)
{
    mmio_write32(EDRV32_PLIC_BASE + PLIC_THRESHOLD, threshold);
}

uint32_t plic_pending(void)
{
    return mmio_read32(EDRV32_PLIC_BASE + PLIC_PENDING);
}

unsigned int plic_claim(void)
{
    return mmio_read32(EDRV32_PLIC_BASE + PLIC_CLAIM);
}

void plic_complete(unsigned int source)
{
    mmio_write32(EDRV32_PLIC_BASE + PLIC_CLAIM, source);
}
