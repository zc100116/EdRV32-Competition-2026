/* File: map088.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_088.
 * Description: Namco 118 banks with PPU A12 wired directly to CHR A16.
 * Clock domain: emulated CPU register writes; mirroring is fixed by the board.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
static uint8 command;
static void write_reg(uint32 address, uint8 value)
{
    if (!(address & 1)) {
        command = value & 7;
    } else if (command < 2) {
        mmc_bankvrom(2, command * 2048, (value & 0x3e) >> 1);
    } else if (command < 6) {
        mmc_bankvrom(1, 0x1000 + (command - 2) * 1024, (value & 0x3f) | 0x40);
    } else {
        mmc_bankrom(8, 0x8000 + (command - 6) * 8192, value & 15);
    }
}
static void init(void)
{
    command = 0;
    mmc_bankrom(8, 0x8000, 0);
    mmc_bankrom(8, 0xa000, 1);
    mmc_bankrom(8, 0xc000, mmc_getinfo()->rom_banks * 2 - 2);
    mmc_bankrom(8, 0xe000, MMC_LASTBANK);
}
static map_memwrite writes[] = {
    {0x8000, 0x9fff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map88_intf = {
    .number = 88, .name = "Namco 118", .init = init, .mem_write = writes
};
