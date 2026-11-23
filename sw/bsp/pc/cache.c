/* File: cache.c
 * Spec: PC design 4.3.
 * Description: Host DDR is coherent; cache ownership operations need no work.
 * Clock domain: host.
 */
#include "cache.h"
void cache_clean(uintptr_t address, uint32_t size) { (void)address; (void)size; }
void cache_invalidate(uintptr_t address, uint32_t size) { (void)address; (void)size; }
void cache_clean_invalidate(uintptr_t address, uint32_t size) { (void)address; (void)size; }
void cache_clean_all(void) {}
