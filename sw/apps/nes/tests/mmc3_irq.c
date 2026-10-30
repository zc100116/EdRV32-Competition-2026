/* File: mmc3_irq.c
 * Spec: T-NES3; https://www.nesdev.org/wiki/MMC3#IRQ_Specifics.
 * Description: Check counter reload, zero IRQ and counting while IRQ is disabled.
 * Clock domain: one mapper hblank clock per rendered scanline.
 */
#include <assert.h>
#include <stdio.h>
#include <noftypes.h>
#include <nes_mmc.h>
#include <nes_ppu.h>

extern mapintf_t map4_intf;
static rominfo_t cart;
static unsigned interrupts;
static bool rendering = true;
static int prg[4];
static int chr[8];
rominfo_t *mmc_getinfo(void) { return &cart; }
void mmc_bankrom(int size, uint32 address, int bank)
{ assert(size == 8); prg[(address - 0x8000) / 0x2000] = bank; }
void mmc_bankvrom(int size, uint32 address, int bank)
{ assert(size == 1); chr[address / 0x400] = bank; }
void ppu_mirror(int a, int b, int c, int d) { (void)a; (void)b; (void)c; (void)d; }
bool ppu_enabled(void) { return rendering; }
void nes_irq(void) { ++interrupts; }
static void write_reg(uint32 address, uint8 value)
{ map4_intf.mem_write[0].write_func(address, value); }
static void clock_line(void) { map4_intf.hblank(0); }
int main(void)
{
    cart.rom_banks = 16;
    map4_intf.init();
    write_reg(0x8000, 6);
    write_reg(0x8001, 9);
    write_reg(0x8000, 0x46);
    assert(prg[0] == 30 && prg[2] == 9);
    write_reg(0x8000, 6);
    assert(prg[0] == 9 && prg[2] == 30);
    write_reg(0x8000, 0);
    write_reg(0x8001, 12);
    write_reg(0x8000, 0x80);
    assert(chr[0] == 4 && chr[4] == 12 && chr[5] == 13);
    write_reg(0x8000, 0);
    assert(chr[0] == 12 && chr[1] == 13 && chr[4] == 4);
    write_reg(0xc000, 2);
    write_reg(0xc001, 0);
    /* The clock must keep running and reloading with IRQ output disabled. */
    for (unsigned i = 0; i < 6; ++i)
        clock_line();
    assert(interrupts == 0);
    write_reg(0xe001, 0);
    clock_line(); /* reload 2 */
    clock_line(); /* 1 */
    assert(interrupts == 0);
    clock_line(); /* 0 */
    assert(interrupts == 1);
    clock_line(); /* reload 2 automatically */
    write_reg(0xc000, 9); /* latch write must not change the live counter */
    clock_line();
    clock_line();
    assert(interrupts == 2);
    write_reg(0xc000, 0);
    write_reg(0xc001, 0);
    clock_line();
    clock_line();
    assert(interrupts == 4); /* MMC3B/C: zero latch interrupts on every clock. */
    rendering = false;
    clock_line();
    rendering = true;
    map4_intf.hblank(1);
    assert(interrupts == 4);
    puts("PASS MMC3 bank mode changes, IRQ reload and disabled counter");
    return 0;
}
