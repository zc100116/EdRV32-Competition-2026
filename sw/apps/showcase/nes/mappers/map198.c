/* File: map198.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_198.
 * Description: MMC3 with 512+128 KiB PRG chips, banked CHR-RAM and 12 KiB WRAM.
 * Clock domain: emulated CPU writes and PPU scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include "mmc3_variants.h"
mapintf_t map198_intf = {
    .number = 198,
    .name = "Xiangfeng Cartoon",
    .init = nes_mmc3_variant_init,
    .hblank = nes_mmc3_variant_hblank,
    .mem_read = nes_mmc3_ram_reads,
    .mem_write = nes_mmc3_ram_writes
};
