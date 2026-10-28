/* File: info.h
 * Spec: edrv32-soc-spec 7.5; cache-spec 2.1.
 * Description: Shared UART fields for ROM startup and the SRAM monitor.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_BOOT_INFO_H
#define EDRV32_BOOT_INFO_H
#include <stdint.h>

/* cache-spec 2.1: configuration constants, not discoverable registers. */
#define SYSTEM_ICACHE_BYTES 8192u
#define SYSTEM_DCACHE_BYTES 8192u
#define SYSTEM_CACHE_WAYS 2u
#define SYSTEM_CACHE_LINE_BYTES 32u

void info_text(const char *key, const char *value);
void info_number(const char *key, uint64_t value);
void info_hex(const char *key, uint32_t value);
void info_ratio(const char *key, uint64_t numerator, uint64_t denominator);
void system_info(void);
#endif
