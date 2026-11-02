/* File: display_command.c
 * Spec: rnd-spec 2.1/2.6; design 2026-10-29-rnd-disp 5.2.
 * Description: Opaque ARGB8888 palette and centered, exact 3x I8 nearest-neighbor BLIT.
 * Clock domain: clk_sys CPU; also exercised by the Linux reference check.
 */
#include "display.h"

int nes_palette_update(uint32_t *packed, const struct nes_rgb *palette)
{
    int changed = 0;
    for (unsigned i = 0; i < 256; ++i) {
        uint32_t color = 0xff000000u | ((uint32_t)palette[i].r << 16) |
                         ((uint32_t)palette[i].g << 8) | palette[i].b;
        if (packed[i] != color) {
            packed[i] = color;
            changed = 1;
        }
    }
    return changed;
}

void nes_blit_encode(struct rnd_command *command, uint32_t target, uint32_t pixels,
                     uint32_t palette)
{
    struct rnd_common common = {
        .dst_base = target, .dst_stride = NES_SCREEN_STRIDE,
        .dst_fmt = RND_RGB565, .src_fmt = RND_I8,
        .clip = {0, 0, NES_SCREEN_WIDTH - 1, NES_SCREEN_HEIGHT - 1},
        .rect = {256, 0, 1023, 719}, .opa = 255
    };
    struct rnd_blit blit = {
        .source = {.base = pixels, .stride = 256},
        /* ceil(65536/3): floor(k * step / 65536) == floor(k/3), k < 768. */
        .scale_x = 21846, .scale_y = 21846, .palette = palette
    };
    rnd_blit(command, &common, &blit);
}
