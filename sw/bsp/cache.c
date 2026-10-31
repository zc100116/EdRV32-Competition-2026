/* File: cache.c
 * Spec: cache-spec 4, 5.4; edrv32-soc-spec 7.4
 * Description: Issue cache maintenance and wait for hardware completion.
 * Clock domain: clk_sys.
 */
#include "cache.h"
#include "soc_map.h"

static void cache_wait(void)
{
    /* SoC 6.1: SRAM_BASE is readable and cacheable, independent of the caller's
     * DDR alias. cache-spec 5.4 delays this load's response until maintenance ends.
     * cpu-spec 4.7 orders all memory accesses; the non-posted OP_CMD store has
     * completed before this load, so no intervening hardware fence is needed.
     */
    (void)*(volatile uint32_t *)EDRV32_SRAM_BASE;
}

static void cache_operation(uintptr_t address, uint32_t size, uint32_t command)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    *(volatile uint32_t *)(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_ADDR) = address;
    *(volatile uint32_t *)(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_SIZE) = size;
    *(volatile uint32_t *)(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_CMD) = command;
    cache_wait();
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

void cache_clean(uintptr_t address, uint32_t size)
{
    cache_operation(address, size, CACHE_CTRL_CMD_CLEAN);
}

void cache_invalidate(uintptr_t address, uint32_t size)
{
    cache_operation(address, size, CACHE_CTRL_CMD_INVALIDATE);
}

void cache_clean_invalidate(uintptr_t address, uint32_t size)
{
    cache_operation(address, size, CACHE_CTRL_CMD_CLEAN_INVALIDATE);
}

void cache_clean_all(void)
{
    cache_operation(0u, 0u, CACHE_CTRL_CMD_CLEAN_ALL);
}
