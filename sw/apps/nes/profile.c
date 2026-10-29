/* File: profile.c
 * Spec: Task B3-4b; design 2026-10-29-rnd-disp 5.2.
 * Description: Measure CPU slices and PPU scanline work without editing the core.
 * Clock domain: platform timebase.
 */
#include <noftypes.h>
#include <nes_ppu.h>
#include "nes_port.h"
int __real_nes6502_execute(int cycles);
void __real_ppu_scanline(bitmap_t *bitmap, int scanline, bool draw);
void __real_ppu_endscanline(int scanline);

int __wrap_nes6502_execute(int cycles)
{
    uint64_t start = nes_ticks();
    int result = __real_nes6502_execute(cycles);
    nes_stats.cpu_ticks += nes_ticks() - start;
    return result;
}

void __wrap_ppu_scanline(bitmap_t *bitmap, int scanline, bool draw)
{
    uint64_t start = nes_ticks();
    __real_ppu_scanline(bitmap, scanline, draw && !nes_skip_render);
    nes_stats.ppu_ticks += nes_ticks() - start;
}

void __wrap_ppu_endscanline(int scanline)
{
    uint64_t start = nes_ticks();
    __real_ppu_endscanline(scanline);
    nes_stats.ppu_ticks += nes_ticks() - start;
}
