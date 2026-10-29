/* File: ranges.c
 * Spec: edrv32-soc-spec 6.1, 7.5(3a); Task B1-10.
 * Description: Host-compiled coverage of the exact BIOS load/run range predicates.
 * Clock domain: none (host test).
 */
#include <stdio.h>
#include "boot.h"

int main(void)
{
    const uint32_t sram_end = EDRV32_SRAM_BASE + EDRV32_SRAM_SIZE - BOOT_STACK_BYTES;
    const uint32_t ddr_end = EDRV32_DDR_BASE + EDRV32_DDR_SIZE;
    const struct {
        uint32_t address;
        uint32_t length;
        int valid;
    } loads[] = {
        {EDRV32_SRAM_BASE, 1u, 1},
        {EDRV32_SRAM_BASE, EDRV32_SRAM_SIZE - BOOT_STACK_BYTES, 1},
        {sram_end - 1u, 1u, 1},
        {sram_end - 1u, 2u, 0},
        {sram_end, 1u, 0},
        {EDRV32_SRAM_BASE - 1u, 2u, 0},
        {EDRV32_SRAM_BASE, 0u, 0},
        {EDRV32_DDR_BASE, EDRV32_DDR_SIZE, 1},
        {EDRV32_DDR_BASE, 1u, 1},
        {EDRV32_DDR_BASE + 1u, EDRV32_DDR_SIZE - 1u, 1},
        {ddr_end - 1u, 1u, 1},
        {ddr_end - 1u, 2u, 0},
        {EDRV32_DDR_BASE - 1u, 2u, 0},
        {EDRV32_DDR_BASE, EDRV32_DDR_SIZE + 1u, 0},
        {EDRV32_DDR_BASE, 0u, 0},
        {EDRV32_DDR_UNCACHED_BASE, 1u, 0},
        {EDRV32_ROM_BASE, 1u, 0},
        {EDRV32_SYS_APB_BASE, 1u, 0},
        {EDRV32_DDR_BASE, UINT32_MAX, 0},
        {UINT32_MAX, 2u, 0},
    };
    const struct {
        uint32_t address;
        int valid;
    } runs[] = {
        {EDRV32_SRAM_BASE, 1}, {EDRV32_SRAM_BASE + 2u, 0},
        {sram_end - 4u, 1}, {sram_end, 0},
        {EDRV32_DDR_BASE, 1}, {EDRV32_DDR_BASE + 1u, 0},
        {ddr_end - 4u, 1}, {ddr_end, 0},
        {EDRV32_DDR_UNCACHED_BASE, 0}, {EDRV32_ROM_BASE, 0},
        {EDRV32_SYS_APB_BASE, 0}, {UINT32_MAX, 0},
    };
    for (unsigned int i = 0; i < sizeof(loads) / sizeof(loads[0]); ++i) {
        int actual = boot_load_range(loads[i].address, loads[i].length);
        if (actual != loads[i].valid) {
            fprintf(stderr, "FAIL load %u expected=%d actual=%d\n", i, loads[i].valid, actual);
            return 1;
        }
    }
    for (unsigned int i = 0; i < sizeof(runs) / sizeof(runs[0]); ++i) {
        int actual = boot_run_address(runs[i].address);
        if (actual != runs[i].valid) {
            fprintf(stderr, "FAIL run %u expected=%d actual=%d\n", i, runs[i].valid, actual);
            return 1;
        }
    }
    puts("PASS BIOS ranges: 20 load + 12 run cases (SRAM, DDR, boundaries, wrap)");
    return 0;
}
