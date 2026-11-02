/* File: map069.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/Sunsoft_FME-7.
 * Description: FME-7 PRG/CHR banks, SRAM/ROM window and CPU-cycle downcounter.
 * Clock domain: emulated CPU cycles, synchronized at register access and hblank.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
#include <nes6502.h>
static uint8 command;
static uint8 bank6000;
static uint8 control;
static uint16 counter;
static uint32 last_cycle;
static void sync_counter(void)
{
    uint32 now = nes6502_getcycles(false);
    uint32 elapsed = now - last_cycle;
    last_cycle = now;
    if (control & 0x80) {
        if (elapsed > counter && (control & 1))
            nes6502_setirq(NES6502_IRQ_MAPPER, true);
        counter = (uint16)(counter - elapsed);
    }
}
static void hblank(int vblank) { (void)vblank; sync_counter(); }
static uint8 read6000(uint32 address)
{
    rominfo_t *cart = mmc_getinfo();
    if (!(bank6000 & 0x40)) {
        int bank = (bank6000 & 0x3f) % (cart->rom_banks * 2);
        return cart->rom[bank * 8192 + (address & 8191)];
    }
    /* Like the upstream CPU's unmapped pages, disabled RAM reads as $FF. */
    return bank6000 & 0x80 ? cart->sram[address & 8191] : 0xff;
}
static void write_reg(uint32 address, uint8 value)
{
    sync_counter();
    if (address < 0x8000) {
        if ((bank6000 & 0xc0) == 0xc0)
            mmc_getinfo()->sram[address & 8191] = value;
        return;
    }
    if (address < 0xa000) {
        command = value & 15;
        return;
    }
    if (command < 8) {
        mmc_bankvrom(1, command * 1024, value);
        return;
    }
    switch (command) {
    case 8: bank6000 = value; break;
    case 9: case 10: case 11:
        mmc_bankrom(8, 0x8000 + (command - 9) * 8192, value & 0x3f);
        break;
    case 12:
        switch (value & 3) {
        case 0: ppu_mirror(0, 1, 0, 1); break;
        case 1: ppu_mirror(0, 0, 1, 1); break;
        case 2: ppu_mirror(0, 0, 0, 0); break;
        case 3: ppu_mirror(1, 1, 1, 1); break;
        }
        break;
    case 13:
        control = value;
        nes6502_setirq(NES6502_IRQ_MAPPER, false);
        break;
    case 14: counter = (counter & 0xff00) | value; break;
    case 15: counter = (counter & 0xff) | (value << 8); break;
    }
}
static void init(void)
{
    command = 0;
    bank6000 = 0xc0;
    counter = 0;
    control = 0;
    last_cycle = nes6502_getcycles(false);
    for (int i = 0; i < 3; ++i)
        mmc_bankrom(8, 0x8000 + i * 8192, i);
    mmc_bankrom(8, 0xe000, MMC_LASTBANK);
}
static map_memread reads[] = {
    {0x6000, 0x7fff, read6000}, {(uint32)-1, (uint32)-1, NULL}
};
static map_memwrite writes[] = {
    {0x6000, 0x7fff, write_reg}, {0x8000, 0xbfff, write_reg},
    {(uint32)-1, (uint32)-1, NULL}
};
mapintf_t map69_intf = {
    .number = 69, .name = "Sunsoft FME-7", .init = init, .hblank = hblank,
    .mem_read = reads, .mem_write = writes
};
