/* File: host_bsp.c
 * Spec: Task B2-3b; SoC 7.4.
 * Description: Link-only host definitions; invoking cache maintenance is a test failure.
 * Clock domain: none (host CPU).
 */
#include <stdlib.h>
#include "cache.h"

/* Task B2-3b: pure tests must never execute hardware cache maintenance. */
void cache_clean(uintptr_t address, uint32_t size)
{
    (void)address;
    (void)size;
    abort();
}

/* Task B2-3b: pure tests must never execute hardware cache maintenance. */
void cache_invalidate(uintptr_t address, uint32_t size)
{
    (void)address;
    (void)size;
    abort();
}
