/* File: map245.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_245.
 * Description: MMC3 with unbanked CHR-RAM and CHR A11 wired to PRG A19.
 * Clock domain: emulated CPU writes and PPU scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include "mmc3_variants.h"
mapintf_t map245_intf = {
    .number = 245,
    .name = "Waixing F003",
    .init = nes_mmc3_variant_init,
    .hblank = nes_mmc3_variant_hblank,
    .mem_write = nes_mmc3_variant_writes
};
