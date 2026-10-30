/* File: map071.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_071.
 * Description: Camerica PRG banks and the iNES Fire Hawk $9000 mirroring latch.
 * Clock domain: emulated CPU register writes.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
static void write_reg(uint32 address, uint8 value)
{
    if (address >= 0xc000)
        mmc_bankrom(16, 0x8000, value & 15);
    else if (address >= 0x9000 && address < 0xa000) {
        int page = (value >> 4) & 1;
        ppu_mirror(page, page, page, page);
    }
}
static map_memwrite writes[] = {
    {0x8000, 0xffff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map71_intf = {
    .number = 71, .name = "Camerica", .mem_write = writes
};
