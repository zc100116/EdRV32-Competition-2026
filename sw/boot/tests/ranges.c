/* File: ranges.c
 * Spec: edrv32-soc-spec 6.1, 7.5(3a); Task B1-10.
 * Description: Host-compiled coverage of the exact BIOS load/run range predicates.
 * Clock domain: none (host test).
 */
#include <stdio.h>
#include "session.h"

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
        {EDRV32_DDR_BASE, EDRV32_DDR_SIZE, 0},
        {EDRV32_DDR_BASE, 1u, 1},
        {EDRV32_DDR_BASE + 1u, EDRV32_DDR_SIZE - 1u, 0},
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
        {0x8a000000u, 1u, 0}, {0x8a010fffu, 1u, 0},
        {0x89ffffffu, 1u, 1}, {0x89ffffffu, 2u, 0},
        {0x8a011000u, 1u, 1}, {0x89fff000u, 0x13000u, 0},
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
        {0x8a000000u, 0}, {0x8a010ffcu, 0}, {0x8a011000u, 1},
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
    uint8_t bytes[136] = {2u, 0u, 0u, 0u, 0u, 1u, 0u, 0x80u,
                         0u, 1u, 0u, 0x80u, 4u, 0u, 0u, 0u,
                         3u, 0u, 0u, 0x10u, 5u, 0u, 0u, 0u};
    struct boot_session session;
    if (!boot_session_parse(&session, bytes) || session.count != 2u ||
        session.entry != 0x80000100u || session.segments[1].address != 0x10000003u ||
        !boot_session_complete(&session, 4u, 29u) ||
        boot_session_complete(&session, 3u, 29u) ||
        boot_session_complete(&session, 4u, 28u) ||
        boot_session_complete(&session, 8u, 29u) ||
        boot_session_complete(&session, 4u, 34u)) return 1;
    bytes[0] = 1u;
    if (!boot_session_parse(&session, bytes) ||
        !boot_session_complete(&session, 4u, 16u)) return 1;
    bytes[0] = 0u;
    if (boot_session_parse(&session, bytes)) return 1;
    bytes[0] = 17u;
    if (boot_session_parse(&session, bytes)) return 1;
    bytes[0] = 2u;
    bytes[4] = 1u;
    if (boot_session_parse(&session, bytes)) return 1;
    bytes[4] = 0u;
    bytes[12] = 0u;
    if (boot_session_parse(&session, bytes)) return 1;
    bytes[12] = 4u;
    bytes[11] = 0x40u;
    if (boot_session_parse(&session, bytes)) return 1;
    /* Maximum segment count is valid; overlapping segments are permitted. */
    for (unsigned int i = 0u; i < 16u; ++i) {
        for (unsigned int j = 0u; j < 8u; ++j) bytes[8u + 8u * i + j] = 0u;
        bytes[11u + 8u * i] = 0x80u;
        bytes[12u + 8u * i] = 1u;
    }
    bytes[0] = 16u;
    if (!boot_session_parse(&session, bytes)) return 1;
    puts("PASS BIOS SRAM/DDR/staging boundaries, entry, descriptor and ETH byte counts");
    return 0;
}
