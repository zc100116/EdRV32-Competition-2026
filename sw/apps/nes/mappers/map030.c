/* File: map030.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/UNROM_512.
 * Description: 16 KiB PRG banks, 32 KiB CHR-RAM and configurable nametables.
 * Clock domain: emulated CPU writes and PPU accesses; flash writes are excluded.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <string.h>
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
#include <nes6502.h>
#include "mapper_chr.h"
static uint8 chr_ram[32768];
static void write_reg(uint32 address, uint8 value)
{
    rominfo_t *cart = mmc_getinfo();
    if (cart->flags & ROM_FLAG_BATTERY) {
        if (address < 0xc000)
            return; /* Flash programming is outside T-NES3. */
    } else {
        value &= nes6502_getbyte(address); /* Non-flash boards have bus conflicts. */
    }
    mmc_bankrom(16, 0x8000, value & 31);
    ppu_setpage(8, 0, chr_ram + ((value >> 5) & 3) * 8192);
    if ((cart->flags & ROM_FLAG_FOURSCREEN) && cart->mirror == MIRROR_HORIZ) {
        int page = value >> 7;
        ppu_mirror(page, page, page, page);
    }
}
static void init(void)
{
    rominfo_t *cart = mmc_getinfo();
    memset(chr_ram, 0, sizeof(chr_ram));
    nes_chr_write_hook = NULL;
    mmc_bankrom(16, 0x8000, 0);
    mmc_bankrom(16, 0xc000, MMC_LASTBANK);
    ppu_setpage(8, 0, chr_ram);
    if (cart->flags & ROM_FLAG_FOURSCREEN) {
        if (cart->mirror == MIRROR_HORIZ)
            ppu_mirror(0, 0, 0, 0);
        else
            ppu_setpage(8, 8, chr_ram + 3 * 8192 - 0x2000);
    }
}
static map_memwrite writes[] = {
    {0x8000, 0xffff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map30_intf = {
    .number = 30, .name = "UNROM 512", .init = init, .mem_write = writes
};
