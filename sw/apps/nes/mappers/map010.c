/* File: map010.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/MMC4.
 * Description: MMC4 16 KiB PRG banks and two tile-triggered 4 KiB CHR latches.
 * Clock domain: emulated CPU writes and PPU tile fetches.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <string.h>
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
static uint8 banks[4];
static uint8 latch[2];
static void latch_tile(uint32 address, uint8 tile)
{
    if (tile == 0xfd || tile == 0xfe) {
        int half = address ? 1 : 0;
        latch[half] = tile - 0xfd;
        mmc_bankvrom(4, half * 4096, banks[half * 2 + latch[half]]);
    }
}
static void write_reg(uint32 address, uint8 value)
{
    int reg = address >> 12;
    if (reg == 0xa)
        mmc_bankrom(16, 0x8000, value & 15);
    else if (reg >= 0xb && reg <= 0xe) {
        int bank = reg - 0xb;
        banks[bank] = value & 31;
        if ((bank & 1) == latch[bank / 2])
            mmc_bankvrom(4, (bank / 2) * 4096, banks[bank]);
    } else if (reg == 0xf) {
        if (value & 1)
            ppu_mirror(0, 0, 1, 1);
        else
            ppu_mirror(0, 1, 0, 1);
    }
}
static void init(void)
{
    memset(banks, 0, sizeof(banks));
    latch[0] = latch[1] = 1;
    mmc_bankrom(16, 0x8000, 0);
    mmc_bankrom(16, 0xc000, MMC_LASTBANK);
    mmc_bankvrom(4, 0, 0);
    mmc_bankvrom(4, 4096, 0);
    ppu_setlatchfunc(latch_tile);
}
static map_memwrite writes[] = {
    {0xa000, 0xffff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map10_intf = {
    .number = 10, .name = "MMC4", .init = init, .mem_write = writes
};
