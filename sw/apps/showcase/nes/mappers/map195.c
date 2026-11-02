/* File: map195.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_195.
 * Description: MMC3 with a CHR-write-controlled GAL and extra PRG-RAM.
 * Clock domain: emulated CPU writes and PPU scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include "mmc3_variants.h"
mapintf_t map195_intf = {
    .number = 195,
    .name = "Waixing FS303",
    .init = nes_mmc3_variant_init,
    .hblank = nes_mmc3_variant_hblank,
    .mem_read = nes_mmc3_ram_reads,
    .mem_write = nes_mmc3_ram_writes
};
