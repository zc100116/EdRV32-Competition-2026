/* File: map199.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_199.
 * Description: Extended PRG MMC3 with unbanked CHR-RAM and 12 KiB WRAM.
 * Clock domain: emulated CPU writes and PPU scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include "mmc3_variants.h"
mapintf_t map199_intf = {
    .number = 199,
    .name = "Waixing FS309",
    .init = nes_mmc3_variant_init,
    .hblank = nes_mmc3_variant_hblank,
    .mem_read = nes_mmc3_ram_reads,
    .mem_write = nes_mmc3_ram_writes
};
