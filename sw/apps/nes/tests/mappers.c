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
#include <nes6502.h>
#include "mapper_chr.h"
extern mapintf_t map74_intf;
extern mapintf_t map192_intf;
extern mapintf_t map195_intf;
extern mapintf_t map191_intf;
extern mapintf_t map199_intf;
extern mapintf_t map245_intf;
extern mapintf_t map69_intf;
extern mapintf_t map30_intf;
extern mapintf_t map140_intf;
static rominfo_t cart;
static uint8 vrom[512 * 1024];
static uint8 *pages[16];
static uint8 bus = 0xff;
uint8 nes6502_getbyte(uint32 address) { (void)address; return bus; }
static int prg[4];
static int mirror[4];
static uint32 cycles;
static bool mapper_irq;
static uint8 sram[8192];
static uint8 rom[1024 * 1024];
uint32 nes6502_getcycles(bool reset) { (void)reset; return cycles; }
rominfo_t *mmc_getinfo(void) { return &cart; }
void mmc_bankrom(int size, uint32 address, int bank)
{
    assert(size == 8 || size == 16 || size == 32);
    for (int i = 0; i < size / 8; ++i)
        prg[(address - 0x8000) / 0x2000 + i] = bank < 0 ? bank : bank * (size / 8) + i;
}
void ppu_setpage(int size, int page, uint8 *location)
{
    for (int i = 0; i < size; ++i)
        pages[page + i] = location;
}
void mmc_bankvrom(int size, uint32 address, int bank)
{
    assert(size == 1 || size == 2 || size == 4 || size == 8);
    if (cart.vrom_banks)
        ppu_setpage(size, address >> 10,
                    vrom + (bank % (cart.vrom_banks * 8 / size)) * size * 1024 - address);
}
void ppu_mirror(int a, int b, int c, int d)
{ mirror[0] = a; mirror[1] = b; mirror[2] = c; mirror[3] = d; }
bool ppu_enabled(void) { return true; }
void nes6502_setirq(uint8 source, bool asserted)
{ assert(source == NES6502_IRQ_MAPPER); mapper_irq = asserted; }
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
static void test199(void)
{
    cart.mapper_number = 199;
    cart.rom_banks = 64;
    map199_intf.init();
    nes_chr_write(0x1000, 0x99);
    chr_bank(&map199_intf, 0xff);
    assert(pages[4][0x1000] == 0x99);
    write_reg(&map199_intf, 0x8000, 6);
    write_reg(&map199_intf, 0x8001, 0x70);
    assert(prg[0] == 0x70);
    write_reg(&map199_intf, 0x5001, 0x33);
    assert(map199_intf.mem_read[0].read_func(0x5001) == 0x33);
}
static void test245(void)
{
    cart.mapper_number = 245;
    cart.vrom_banks = 0;
    map245_intf.init();
    write_reg(&map245_intf, 0x8000, 0);
    write_reg(&map245_intf, 0x8001, 2);
    assert(prg[0] == 0x40 && prg[2] == 0x7e && prg[3] == 0x7f);
    nes_chr_write(0x1000, 0x66);
    write_reg(&map245_intf, 0x8001, 0);
    assert(prg[0] == 0 && prg[2] == 0x3e && prg[3] == 0x3f);
    assert(pages[4][0x1000] == 0x66);
}
static void command69(uint8 command, uint8 value)
{
    write_reg(&map69_intf, 0x8000, command);
    write_reg(&map69_intf, 0xa000, value);
}
static void test69(void)
{
    cart.sram = sram;
    cart.rom = rom;
    cart.rom_banks = 64;
    map69_intf.init();
    command69(9, 7);
    assert(prg[0] == 7);
    command69(8, 0xc0);
    write_reg(&map69_intf, 0x6123, 0x69);
    assert(map69_intf.mem_read[0].read_func(0x6123) == 0x69);
    rom[3 * 8192 + 0x123] = 0x43;
    command69(8, 3);
    assert(map69_intf.mem_read[0].read_func(0x6123) == 0x43);
    command69(14, 2);
    command69(15, 0);
    command69(13, 0x81);
    cycles += 2;
    map69_intf.hblank(0);
    assert(!mapper_irq);
    ++cycles;
    map69_intf.hblank(0);
    assert(mapper_irq);
    command69(13, 0x80);
    assert(!mapper_irq);
    cycles += 65536;
    map69_intf.hblank(1);
    assert(!mapper_irq); /* count continues with output disabled */
}
static void test30(void)
{
    cart.flags = ROM_FLAG_BATTERY | ROM_FLAG_FOURSCREEN;
    cart.mirror = MIRROR_HORIZ;
    map30_intf.init();
    write_reg(&map30_intf, 0xc000, 0xa3);
    assert(prg[0] == 6 && mirror[0] == 1 && mirror[3] == 1);
    pages[0][0] = 0x30;
    write_reg(&map30_intf, 0xc000, 0);
    assert(pages[0][0] == 0);
    write_reg(&map30_intf, 0xc000, 0xa3);
    assert(pages[0][0] == 0x30);
    write_reg(&map30_intf, 0x8000, 5);
    assert(prg[0] == 6); /* Flash command space does not bank-switch. */
    cart.flags = 0;
    bus = 0x21;
    write_reg(&map30_intf, 0x8000, 0xff);
    assert(prg[0] == 2);
    bus = 0xff;
}
static void test140(void)
{
    cart.vrom_banks = 32;
    map140_intf.init();
    write_reg(&map140_intf, 0x6000, 0x2b);
    assert(prg[0] == 8 && prg[3] == 11);
    assert(pages[0] == vrom + 11 * 8192);
}
int main(void)
{
    test74();
    test192();
    test195();
    test191();
    test199();
    test245();
    test69();
    test30();
    test140();
    puts("PASS mapper bank wiring and CHR memory");
    return 0;
}
