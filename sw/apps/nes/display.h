/* File: display.h
 * Spec: rnd-spec 2.1/2.6/5.4; disp-spec 5.3; Task B3-4b step 2.
 * Description: Shared palette/BLIT encoding and the board's asynchronous L0 sink.
 * Clock domain: clk_sys CPU; RND/DISP in clk_mem.
 */
#ifndef NES_DISPLAY_H
#define NES_DISPLAY_H
#include "nes_port.h"
#include "rnd.h"

enum {
    NES_SCREEN_WIDTH = 1280,
    NES_SCREEN_HEIGHT = 720,
    NES_SCREEN_STRIDE = 2560,
    NES_SCREEN_BYTES = NES_SCREEN_STRIDE * NES_SCREEN_HEIGHT
};
int nes_palette_update(uint32_t *packed, const struct nes_rgb *palette);
void nes_blit_encode(struct rnd_command *command, uint32_t target, uint32_t pixels,
                     uint32_t palette);
void nes_display_init(void);
void nes_display_frame(const uint8_t *pixels, const struct nes_rgb *palette);
#endif
