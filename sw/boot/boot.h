/* File: boot.h
 * Spec: edrv32-soc-spec 7.5
 * Description: UART download request convention and application handoff.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_BOOT_H
#define EDRV32_BOOT_H
#include <stdint.h>
#include "soc_map.h"

#define BOOT_BUTTON_BIT 0u
#define BOOT_BUTTON_ACTIVE 0u
#define BOOT_DOWNLOAD_MAGIC 0x55415254u

static inline int boot_download_requested(uint32_t gpio, uint32_t scratch)
{
    return (((gpio >> BOOT_BUTTON_BIT) & 1u) == BOOT_BUTTON_ACTIVE) ||
           scratch == BOOT_DOWNLOAD_MAGIC;
}

_Noreturn void boot_enter(uintptr_t entry);
#endif
