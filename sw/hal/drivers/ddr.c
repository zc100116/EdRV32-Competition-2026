/* ============================================================================
 * File        : ddr.c
 * Description : Small deterministic DDR tests used by software bring-up cases.
 * ========================================================================== */
#include "edrv32_ddr.h"
#include "edrv32_mmio.h"

static unsigned int ddr_pattern(unsigned int seed, unsigned int index)
{
    unsigned int value;

    value = seed ^ (index * 0x9e3779b9u);
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
}

int edrv32_ddr_test_uncached(unsigned int offset,
                             unsigned int word_count,
                             unsigned int seed,
                             unsigned int *bad_index,
                             unsigned int *expected,
                             unsigned int *actual)
{
    volatile unsigned int *memory;
    unsigned int index;
    unsigned int want;
    unsigned int got;

    if (((offset & 3u) != 0u) || (offset > SOC_DDR_SIZE) ||
        (word_count > (SOC_DDR_SIZE - offset) / 4u))
        return EDRV32_DDR_BAD_ARGUMENT;

    memory = (volatile unsigned int *)edrv32_ddr_uncached_address(offset);
    for (index = 0; index < word_count; index++)
        memory[index] = ddr_pattern(seed, index);

    edrv32_mmio_fence();

    for (index = 0; index < word_count; index++) {
        want = ddr_pattern(seed, index);
        got = memory[index];
        if (got != want) {
            if (bad_index != (unsigned int *)0)
                *bad_index = index;
            if (expected != (unsigned int *)0)
                *expected = want;
            if (actual != (unsigned int *)0)
                *actual = got;
            return EDRV32_DDR_MISMATCH;
        }
    }

    return EDRV32_DDR_OK;
}

int edrv32_ddr_test_alias(unsigned int offset,
                          unsigned int value,
                          unsigned int *actual)
{
    volatile unsigned int *uncached;
    volatile unsigned int *cached;
    unsigned int got;

    if ((offset & 3u) != 0u || offset > SOC_DDR_SIZE - 4u)
        return EDRV32_DDR_BAD_ARGUMENT;

    uncached = (volatile unsigned int *)edrv32_ddr_uncached_address(offset);
    cached = (volatile unsigned int *)edrv32_ddr_cached_address(offset);
    *uncached = value;
    edrv32_mmio_fence();
    got = *cached;
    if (actual != (unsigned int *)0)
        *actual = got;

    return (got == value) ? EDRV32_DDR_OK : EDRV32_DDR_MISMATCH;
}
