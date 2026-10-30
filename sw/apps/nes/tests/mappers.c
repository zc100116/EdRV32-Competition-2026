/* File: mappers.c
 * Spec: T-NES3; NESdev descriptions linked by each mapper source.
 * Description: Check mapper bank wiring and writable CHR-RAM through mapintf_t.
 * Clock domain: emulated register accesses.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>
#include "mapper_chr.h"
extern mapintf_t map74_intf;
extern mapintf_t map192_intf;
extern mapintf_t map195_intf;
extern mapintf_t map191_intf;
static rominfo_t cart;
static uint8 vrom[512 * 1024];
static uint8 *pages[8];
static int prg[4];
static int mirror[4];
rominfo_t *mmc_getinfo(void) { return &cart; }
void mmc_bankrom(int size, uint32 address, int bank)
{
    assert(size == 8);
    prg[(address - 0x8000) / 0x2000] = bank;
}
void ppu_setpage(int size, int page, uint8 *location)
{
    for (int i = 0; i < size; ++i)
        pages[page + i] = location;
}
void mmc_bankvrom(int size, uint32 address, int bank)
{
    assert(size == 1);
    if (cart.vrom_banks)
        ppu_setpage(1, address >> 10,
                    vrom + (bank % (cart.vrom_banks * 8)) * 1024 - address);
}
void ppu_mirror(int a, int b, int c, int d)
{ mirror[0] = a; mirror[1] = b; mirror[2] = c; mirror[3] = d; }
bool ppu_enabled(void) { return true; }
void nes_irq(void) {}
static void write_reg(mapintf_t *mapper, uint32 address, uint8 value)
{
    for (map_memwrite *entry = mapper->mem_write; entry->write_func; ++entry) {
        if (address >= entry->min_range && address <= entry->max_range) {
            entry->write_func(address, value);
            return;
        }
    }
    assert(0 && "test wrote an unmapped register");
}
static void chr_bank(mapintf_t *mapper, unsigned bank)
{
    write_reg(mapper, 0x8000, 2);
    write_reg(mapper, 0x8001, bank);
}
static void test74(void)
{
    cart.mapper_number = 74;
    cart.rom_banks = 16;
    cart.vrom_banks = 32;
    map74_intf.init();
    chr_bank(&map74_intf, 8);
    assert(nes_chr_write(0x1000, 0xab));
    assert(pages[4][0x1000] == 0xab);
    chr_bank(&map74_intf, 9);
    assert(pages[4][0x1000] == 0);
    assert(nes_chr_write(0x1000, 0xcd));
    chr_bank(&map74_intf, 8);
    assert(pages[4][0x1000] == 0xab);
    chr_bank(&map74_intf, 10);
    assert(nes_chr_write(0x1000, 0xff));
    assert(pages[4][0x1000] == 0); /* CHR-ROM is never writable. */
}
static void test192(void)
{
    cart.mapper_number = 192;
    map192_intf.init();
    chr_bank(&map192_intf, 10);
    nes_chr_write(0x1000, 0x42);
    chr_bank(&map192_intf, 11);
    assert(pages[4][0x1000] == 0);
    chr_bank(&map192_intf, 10);
    assert(pages[4][0x1000] == 0x42);
    chr_bank(&map192_intf, 12);
    nes_chr_write(0x1000, 0x99);
    assert(pages[4][0x1000] == 0);
}
static void test195(void)
{
    cart.mapper_number = 195;
    map195_intf.init();
    chr_bank(&map195_intf, 0x28);
    nes_chr_write(0x1000, 0x55);
    assert(pages[4][0x1000] == 0x55);
    chr_bank(&map195_intf, 0x82); /* GAL selects RAM at banks 0-3. */
    nes_chr_write(0x1000, 0);
    chr_bank(&map195_intf, 0);
    assert(pages[4][0x1000] == 0x55); /* $28 and $00 share physical RAM. */
    chr_bank(&map195_intf, 0x88); /* Select RAM at banks $4C-$4F. */
    nes_chr_write(0x1000, 0);
    chr_bank(&map195_intf, 0x4c);
    assert(pages[4][0x1000] == 0);
    nes_chr_write(0x1000, 0xaa);
    chr_bank(&map195_intf, 0xca); /* Disable all RAM. */
    nes_chr_write(0x1000, 0);
    chr_bank(&map195_intf, 0x4c);
    assert(pages[4][0x1000] == 0);
    write_reg(&map195_intf, 0x5123, 0x42);
    assert(map195_intf.mem_read[0].read_func(0x5123) == 0x42);
}
static void test191(void)
{
    cart.mapper_number = 191;
    cart.vrom_banks = 16;
    map191_intf.init();
    chr_bank(&map191_intf, 0x80);
    nes_chr_write(0x1000, 0x77);
    chr_bank(&map191_intf, 0x82);
    assert(pages[4][0x1000] == 0x77); /* 2 KiB RAM mirrored. */
    cart.vrom_banks = 32;
    map191_intf.init();
    assert(prg[2] == 0x18 && prg[3] == 0x19);
    write_reg(&map191_intf, 0x90aa, 3);
    assert(prg[2] == 0x1e && prg[3] == 0x1f);
    chr_bank(&map191_intf, 0x80);
    nes_chr_write(0x1000, 0x88);
    assert(pages[4][0x1000] == 0x88);
}
int main(void)
{
    test74();
    test192();
    test195();
    test191();
    puts("PASS mapper bank wiring and CHR memory");
    return 0;
}
