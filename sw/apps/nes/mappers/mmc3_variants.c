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

static bool ram_bank(int bank)
{
    return bank == 8 || bank == 9;
}

static void sync_banks(void)
{
    int fixed = mmc_getinfo()->rom_banks * 2 - 2;
    mmc_bankrom(8, 0x8000, command & 0x40 ? fixed : banks[6]);
    mmc_bankrom(8, 0xa000, banks[7]);
    mmc_bankrom(8, 0xc000, command & 0x40 ? banks[6] : fixed);
    mmc_bankrom(8, 0xe000, MMC_LASTBANK);
    int base = command & 0x80 ? 4 : 0;
    int selected[8] = {banks[0] & 0xfe, banks[0] | 1, banks[1] & 0xfe,
                       banks[1] | 1, banks[2], banks[3], banks[4], banks[5]};
    for (int i = 0; i < 8; ++i) {
        int page = i ^ base;
        int bank = selected[i];
        chr_banks[page] = bank;
        chr_writable[page] = ram_bank(bank);
        if (chr_writable[page])
            ppu_setpage(1, page, chr_ram + (bank & 1) * 1024 - page * 1024);
        else
            mmc_bankvrom(1, page * 1024, bank);
    }
}

static bool chr_write(uint32 address, uint8 value)
{
    int page = address >> 10;
    if (chr_writable[page])
        chr_ram[(chr_banks[page] & 1) * 1024 + (address & 1023)] = value;
    return true;
}

static void write_reg(uint32 address, uint8 value)
{
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
    nes_chr_write_hook = chr_write;
    sync_banks();
}

void nes_mmc3_variant_hblank(int vblank) { map4_intf.hblank(vblank); }
map_memwrite nes_mmc3_variant_writes[] = {
    {0x8000, 0xffff, write_reg},
    {(uint32)-1, (uint32)-1, NULL}
};
