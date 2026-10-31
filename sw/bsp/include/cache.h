/* File: cache.h
 * Spec: cache-spec 3.2, 4, 5.4
 * Description: Blocking cache maintenance interface and register definitions.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_CACHE_H
#define EDRV32_CACHE_H
#include <stdint.h>

#define CACHE_CTRL_ID 0x000u
#define CACHE_CTRL_STATUS 0x008u
#define CACHE_CTRL_IRQ_EN 0x00cu
#define CACHE_CTRL_IRQ_STAT 0x010u
#define CACHE_CTRL_ERR_ADDR 0x014u
#define CACHE_CTRL_OP_ADDR 0x020u
#define CACHE_CTRL_OP_SIZE 0x024u
#define CACHE_CTRL_OP_CMD 0x028u
#define CACHE_CTRL_STATUS_BUSY 1u
#define CACHE_CTRL_IRQ_WB_ERROR 2u
#define CACHE_CTRL_CMD_CLEAN 1u
#define CACHE_CTRL_CMD_INVALIDATE 2u
#define CACHE_CTRL_CMD_CLEAN_INVALIDATE 3u
#define CACHE_CTRL_CMD_CLEAN_ALL 4u

/* cache-spec 5.4: return after a cacheable SRAM read observes completion. */
void cache_clean(uintptr_t address, uint32_t size);
void cache_invalidate(uintptr_t address, uint32_t size);
void cache_clean_invalidate(uintptr_t address, uint32_t size);
void cache_clean_all(void);
#endif
