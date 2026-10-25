/* ============================================================================
 * File        : edrv32_ddr.h
 * Description : CPU-visible DDR address and software-memory-test helpers.
 * Notes       : DMA buffers should normally use the uncached alias.  Cache
 *               maintenance is a separate HAL responsibility.
 * ========================================================================== */
#ifndef EDRV32_DDR_H
#define EDRV32_DDR_H

#include "edrv32_soc_map.h"

#define EDRV32_DDR_OK             0
#define EDRV32_DDR_BAD_ARGUMENT  -1
#define EDRV32_DDR_MISMATCH      -2

static inline unsigned int edrv32_ddr_cached_address(unsigned int offset)
{
    return SOC_DDR_BASE + offset;
}

static inline unsigned int edrv32_ddr_uncached_address(unsigned int offset)
{
    return SOC_DDR_UNCACHED_BASE + offset;
}

int edrv32_ddr_test_uncached(unsigned int offset,
                             unsigned int word_count,
                             unsigned int seed,
                             unsigned int *bad_index,
                             unsigned int *expected,
                             unsigned int *actual);

int edrv32_ddr_test_alias(unsigned int offset,
                          unsigned int value,
                          unsigned int *actual);

#endif /* EDRV32_DDR_H */
