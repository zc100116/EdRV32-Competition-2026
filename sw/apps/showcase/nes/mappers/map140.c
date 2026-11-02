/* File: map140.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_140.
 * Description: Jaleco PRG/CHR latch, without ROM bus conflicts.
 * Clock domain: emulated CPU register writes.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
static void write_reg(uint32 address, uint8 value)
{
    (void)address;
    mmc_bankrom(32, 0x8000, (value >> 4) & 3);
    mmc_bankvrom(8, 0, value & 15);
}
static void init(void) { write_reg(0x6000, 0); }
static map_memwrite writes[] = {
    {0x6000, 0x7fff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map140_intf = {
    .number = 140, .name = "Jaleco JF-11/14", .init = init, .mem_write = writes
};
