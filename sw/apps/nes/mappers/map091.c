/* File: map091.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_091.
 * Description: JY830623C (iNES/submapper 0) banks and 64-rise IRQ counter.
 * Clock domain: nofrendo scanline callbacks approximate eight unfiltered A12 rises.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
#include <nes6502.h>
static uint8 prg[2];
static uint8 chr[4];
static uint8 outer;
static unsigned counter;
static bool enabled;
static void sync_banks(void)
{
    int high = (outer & 6) << 3;
    mmc_bankrom(8, 0x8000, high | (prg[0] & 15));
    mmc_bankrom(8, 0xa000, high | (prg[1] & 15));
    mmc_bankrom(8, 0xc000, high | 14);
    mmc_bankrom(8, 0xe000, high | 15);
    for (int i = 0; i < 4; ++i)
        mmc_bankvrom(2, i * 2048, ((outer & 1) << 8) | chr[i]);
}
static void write_reg(uint32 address, uint8 value)
{
    if (address >= 0x8000) {
        outer = address & 7;
        sync_banks();
    } else if (address < 0x7000) {
        chr[address & 3] = value;
        sync_banks();
    } else {
        switch (address & 3) {
        case 0: case 1:
            prg[address & 1] = value;
            sync_banks();
            break;
        case 2: case 3:
            counter = 0;
            enabled = address & 1;
            nes6502_setirq(NES6502_IRQ_MAPPER, false);
            break;
        }
    }
}
static void hblank(int vblank)
{
    if (!vblank && ppu_enabled() && enabled && counter < 8 && ++counter == 8)
        nes6502_setirq(NES6502_IRQ_MAPPER, true);
}
static void init(void)
{
    prg[0] = 0;
    prg[1] = 1;
    for (unsigned i = 0; i < 4; ++i)
        chr[i] = i;
    outer = counter = 0;
    enabled = false;
    sync_banks();
}
static map_memwrite writes[] = {
    {0x6000, 0x9fff, write_reg}, {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map91_intf = {
    .number = 91, .name = "JY830623C", .init = init, .hblank = hblank, .mem_write = writes
};
