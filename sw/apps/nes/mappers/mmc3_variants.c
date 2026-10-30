/* File: mmc3_variants.c
 * Spec: Task T-NES3; https://www.nesdev.org/wiki/INES_Mapper_074.
 * Description: MMC3 registers with cartridge-specific CHR-ROM/RAM decoding.
 * Clock domain: emulated CPU writes, PPU accesses and scanlines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
#include <string.h>
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
#include "mapper_chr.h"
#include "mmc3_variants.h"

extern mapintf_t map4_intf;
static uint8 command;
static uint8 banks[8];
static uint8 chr_ram[8192];
static int chr_banks[8];
static bool chr_writable[8];
static uint8 extra_ram[4096];
static int ram_first;
static int ram_mask;
static uint8 outer;

static int ram_index(int bank)
{
    /* https://www.nesdev.org/wiki/INES_Mapper_191 */
    if (mmc_getinfo()->mapper_number == 199 || mmc_getinfo()->vrom_banks == 0)
        return bank & 7;
    if (mmc_getinfo()->mapper_number == 191)
        return outer == 3 && (bank & 0x80) ? bank & 1 : -1;
    /* https://www.nesdev.org/wiki/INES_Mapper_195: GAL-selected RAM window. */
    if (mmc_getinfo()->mapper_number == 195)
        return (bank & ram_mask) == ram_first ? bank & 7 : -1;
    /* https://www.nesdev.org/wiki/INES_Mapper_192 */
    int count = mmc_getinfo()->mapper_number == 192 ? 4 : 2;
    return bank >= 8 && bank < 8 + count ? bank - 8 : -1;
}

static void sync_banks(void)
{
    int fixed = mmc_getinfo()->rom_banks * 2 - 2;
    bool multicart = mmc_getinfo()->mapper_number == 191 && mmc_getinfo()->vrom_banks == 32;
    if (multicart)
        fixed = 0x18 + outer * 2;
    int prg6 = banks[6];
    int prg7 = banks[7];
    int last = multicart ? fixed + 1 : MMC_LASTBANK;
    /* https://www.nesdev.org/wiki/INES_Mapper_245: CHR A11 becomes PRG A19. */
    if (mmc_getinfo()->mapper_number == 245) {
        int high = (banks[command & 0x80 ? 2 : 0] & 2) << 5;
        fixed = 0x3e | high;
        last = 0x3f | high;
        prg6 = (prg6 & 0x3f) | high;
        prg7 = (prg7 & 0x3f) | high;
    }
    mmc_bankrom(8, 0x8000, command & 0x40 ? fixed : prg6);
    mmc_bankrom(8, 0xa000, prg7);
    mmc_bankrom(8, 0xc000, command & 0x40 ? prg6 : fixed);
    mmc_bankrom(8, 0xe000, last);
    int base = command & 0x80 ? 4 : 0;
    int selected[8] = {banks[0] & 0xfe, banks[0] | 1, banks[1] & 0xfe,
                       banks[1] | 1, banks[2], banks[3], banks[4], banks[5]};
    for (int i = 0; i < 8; ++i) {
        int page = i ^ base;
        int bank = selected[i];
        /* https://www.nesdev.org/wiki/INES_Mapper_199: unbanked CHR-RAM. */
        if (mmc_getinfo()->mapper_number == 199 || mmc_getinfo()->mapper_number == 245)
            bank = page;
        chr_banks[page] = bank;
        chr_writable[page] = ram_index(bank) >= 0;
        if (chr_writable[page])
            ppu_setpage(1, page, chr_ram + ram_index(bank) * 1024 - page * 1024);
        else {
            if (mmc_getinfo()->mapper_number == 191)
                bank = (bank & 0x7f) | (outer != 3 ? 0x80 : 0);
            mmc_bankvrom(1, page * 1024, bank);
        }
    }
}

static bool chr_write(uint32 address, uint8 value)
{
    int page = address >> 10;
    int bank = chr_banks[page];
    if (mmc_getinfo()->mapper_number == 195 && (bank & 0x80)) {
        /* The GAL observes the CHR bank address on PPU writes, not data. */
        ram_mask = bank & 0x40 ? 0xfe : 0xfc;
        switch (bank & 0xda) {
        case 0x80: ram_first = 0x28; break;
        case 0x82: ram_first = 0x00; break;
        case 0x88: ram_first = 0x4c; break;
        case 0x8a: ram_first = 0x64; break;
        case 0xc0: ram_first = 0x46; break;
        case 0xc2: ram_first = 0x7c; break;
        case 0xc8: ram_first = 0x0a; break;
        default: ram_first = -1; break; /* ROM only (D bit or $CA). */
        }
        sync_banks();
    }
    if (chr_writable[page])
        chr_ram[ram_index(bank) * 1024 + (address & 1023)] = value;
    return true;
}

static void write_reg(uint32 address, uint8 value)
{
    if (address < 0x6000) {
        extra_ram[address & 0xfff] = value;
        return;
    }
    if (mmc_getinfo()->mapper_number == 191 && mmc_getinfo()->vrom_banks == 32 &&
        (address & 0xf0ff) == 0x90aa) {
        outer = value & 3;
        sync_banks();
        return;
    }
    switch (address & 0xe001) {
    case 0x8000:
        command = value;
        sync_banks();
        break;
    case 0x8001:
        banks[command & 7] = value;
        sync_banks();
        break;
    case 0xa000:
        /* Waixing clones decode two additional single-screen modes. */
        switch (value & 3) {
        case 0: ppu_mirror(0, 1, 0, 1); break;
        case 1: ppu_mirror(0, 0, 1, 1); break;
        case 2: ppu_mirror(0, 0, 0, 0); break;
        case 3: ppu_mirror(1, 1, 1, 1); break;
        }
        break;
    default:
        map4_intf.mem_write[0].write_func(address, value);
        break;
    }
}

void nes_mmc3_variant_init(void)
{
    static const uint8 initial[8] = {0, 2, 4, 5, 6, 7, 0, 1};
    map4_intf.init();
    command = 0;
    memcpy(banks, initial, sizeof(banks));
    memset(chr_ram, 0, sizeof(chr_ram));
    memset(extra_ram, 0, sizeof(extra_ram));
    outer = mmc_getinfo()->vrom_banks == 32 ? 0 : 3;
    ram_first = 0x28;
    ram_mask = 0xfc;
    nes_chr_write_hook = chr_write;
    sync_banks();
}

void nes_mmc3_variant_hblank(int vblank) { map4_intf.hblank(vblank); }
map_memwrite nes_mmc3_variant_writes[] = {
    {0x8000, 0xffff, write_reg},
    {(uint32)-1, (uint32)-1, NULL}
};

static uint8 read_ram(uint32 address) { return extra_ram[address & 0xfff]; }
map_memread nes_mmc3_ram_reads[] = {
    {0x5000, 0x5fff, read_ram},
    {(uint32)-1, (uint32)-1, NULL}
};
map_memwrite nes_mmc3_ram_writes[] = {
    {0x5000, 0x5fff, write_reg},
    {0x8000, 0xffff, write_reg},
    {(uint32)-1, (uint32)-1, NULL}
};
