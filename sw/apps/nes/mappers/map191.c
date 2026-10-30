/* File: map191.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_191.
 * Description: MMC3 with 2 KiB CHR-RAM and optional 4-in-1 outer bank.
 * Clock domain: emulated CPU writes and PPU scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include "mmc3_variants.h"
mapintf_t map191_intf = {
    .number = 191,
    .name = "Xianfeng Cartoon",
    .init = nes_mmc3_variant_init,
    .hblank = nes_mmc3_variant_hblank,
    .mem_write = nes_mmc3_variant_writes
};
