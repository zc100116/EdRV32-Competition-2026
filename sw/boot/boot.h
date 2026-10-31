/* File: boot.h
 * Spec: edrv32-soc-spec 7.5
 * Description: BIOS request convention, KEY1 sample window and application handoff.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_BOOT_H
#define EDRV32_BOOT_H
#include <stdint.h>
#include "soc_map.h"

#define BOOT_BUTTON_BIT 0u
#define BOOT_BUTTON_ACTIVE 0u
#define BOOT_DOWNLOAD_MAGIC 0x55415254u
#define BOOT_BUTTON_WINDOW_MS 100u
#define BOOT_STACK_BYTES 4096u
#define BOOT_ETH_STAGE_PHYSICAL 0x0a000000u
#define BOOT_ETH_STAGE_BYTES (68u * 1024u)
/* RTL8211F responds at broadcast PHYAD 0; coordinator confirmed board contract. */
#define BOOT_PHY_ADDRESS 0u

static inline int boot_download_requested(uint32_t gpio, uint32_t scratch)
{
    return (((gpio >> BOOT_BUTTON_BIT) & 1u) == BOOT_BUTTON_ACTIVE) ||
           scratch == BOOT_DOWNLOAD_MAGIC;
}

/* SoC 7.5(3a): the complete nonempty interval must fit one loadable region.
 * Subtract only after establishing the address belongs to that region, so
 * a wrapping address+length cannot turn an invalid interval into a valid one.
 */
static inline int boot_load_range(uint32_t address, uint32_t length)
{
    uint32_t sram_end = EDRV32_SRAM_BASE + EDRV32_SRAM_SIZE - BOOT_STACK_BYTES;
    uint32_t ddr_end = EDRV32_DDR_BASE + EDRV32_DDR_SIZE;
    return length != 0u &&
           ((address >= EDRV32_SRAM_BASE && address < sram_end &&
             length <= sram_end - address) ||
            (address >= EDRV32_DDR_BASE && address < ddr_end &&
             length <= ddr_end - address &&
             (address >= EDRV32_DDR_BASE + BOOT_ETH_STAGE_PHYSICAL + BOOT_ETH_STAGE_BYTES ||
              (address < EDRV32_DDR_BASE + BOOT_ETH_STAGE_PHYSICAL &&
               length <= EDRV32_DDR_BASE + BOOT_ETH_STAGE_PHYSICAL - address))));
}

static inline int boot_run_address(uint32_t address)
{
    return (address & 3u) == 0u && boot_load_range(address, 1u);
}

_Noreturn void boot_enter(uintptr_t entry);
#endif
