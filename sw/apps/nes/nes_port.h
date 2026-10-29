/* File: nes_port.h
 * Spec: design 2026-10-29-rnd-disp 5.2; Task B3-4b.
 * Description: Synchronous I8 frame sink and platform timing/input contract.
 * Clock domain: clk_sys on board; monotonic host clock on Linux.
 */
#ifndef NES_PORT_H
#define NES_PORT_H
#include <stdint.h>

struct nes_rgb { uint8_t r, g, b; };
struct nes_stats {
    uint64_t cpu_ticks;
    uint64_t ppu_ticks;
    uint64_t frame_ticks;
};
extern struct nes_stats nes_stats;
extern unsigned nes_frames;
extern unsigned nes_frame_limit;
extern int nes_skip_render;
uint64_t nes_ticks(void);
uint64_t nes_tick_hz(void);
uint64_t nes_instructions(void);
unsigned nes_buttons(void);
/* Pixels: 240 rows, 256 bytes/row. Palette: 256 RGB888 entries.
 * Both pointers remain valid until the next frame; sink returns synchronously.
 */
void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame);
void nes_run(void);
void nes_report(uint64_t elapsed, uint64_t instructions);
#endif
