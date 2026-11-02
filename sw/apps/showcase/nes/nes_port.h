/* File: nes_port.h
 * Spec: showcase design 4.4; nofrendo frame interface.
 * Description: Synchronous I8 frame sink and platform timing/input contract.
 * Clock domain: clk_sys on board; monotonic host clock on Linux.
 */
#ifndef NES_PORT_H
#define NES_PORT_H
#include <stdint.h>

struct nes_rgb { uint8_t r, g, b; };
extern unsigned nes_frames;
extern volatile unsigned nes_shown;
extern unsigned nes_frame_limit;
extern int nes_skip_render;
uint64_t nes_ticks(void);
uint64_t nes_tick_hz(void);
uint64_t nes_instructions(void);
unsigned nes_buttons(void);
/* T-VIN1: protocol U D L R A B Select Start -> NES A B Select Start U D L R. */
static inline unsigned nes_merge_virtual(unsigned buttons, uint16_t keys)
{
    return buttons | ((keys >> 4) & 15u) | ((keys & 15u) << 4);
}
/* Pixels: 240 rows, 256 bytes/row. Palette: 256 RGB888 entries.
 * Both pointers remain valid until the next frame; sink returns synchronously.
 */
void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame);
void nes_start(void);
void nes_step(void);
void nes_stop(void);
void nes_run(void);
#endif
