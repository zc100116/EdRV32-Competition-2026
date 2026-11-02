/* File: map087.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_087.
 * Description: J87 CHR banking including the 32 KiB JF-09/JF-10 variant.
 * Clock domain: emulated CPU register writes.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
static void write_reg(uint32 address, uint8 value)
{
    (void)address;
    mmc_bankvrom(8, 0, ((value & 1) << 1) | ((value >> 1) & 1));
}
static map_memwrite writes[] = {
    {0x6000, 0x7fff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map87_intf = {
    .number = 87, .name = "Jaleco J87", .mem_write = writes
};
