/* File: map192.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_192.
 * Description: MMC3 with banks 8-11 selecting 4 KiB CHR-RAM.
 * Clock domain: emulated CPU writes and PPU scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include "mmc3_variants.h"
mapintf_t map192_intf = {
    .number = 192,
    .name = "Waixing FS308",
    .init = nes_mmc3_variant_init,
    .hblank = nes_mmc3_variant_hblank,
    .mem_write = nes_mmc3_variant_writes
};
