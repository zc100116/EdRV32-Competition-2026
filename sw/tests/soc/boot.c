/* File: boot.c
 * Spec: CLAUDE.md 9.2; edrv32-soc-spec 6.1.
 * Description: Use the generated SRAM base for the preloaded SoC verification program.
 * Clock domain: clk_sys.
 */
#include "soc_map.h"
void __attribute__((noreturn)) boot_entry(void)
{
    __asm__ volatile ("jr %0" :: "r"(EDRV32_SRAM_BASE));
    __builtin_unreachable();
}
