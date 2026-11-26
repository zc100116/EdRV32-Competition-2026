/* hud_test.c — gpu-spec 2.7–2.8; batch alignment and complete HUD glyph regression.
 * Host frame thread, actual application lists and PC GPU reference renderer.
 */
#define main capture_main
#include "../../gpu_test/headless.c"
#undef main
#include "font8x16.h"

static void text_pixels(int x, int y, const char *text, uint16_t color)
{
    const uint16_t *surface = test.surface[test.frame & 1];
    for (; *text; ++text, x += 8) {
        unsigned glyph = (unsigned char)*text - 32;
        for (unsigned row = 0; row < 16; ++row)
            for (unsigned col = 0; col < 8; ++col) {
                uint16_t expected = font8x16[glyph][row] & (128u >> col) ? color : 0x0865;
                uint16_t actual = surface[(y + row) * 640 + x + col];
                if (actual != expected) {
                    fprintf(stderr, "HUD '%c' (%u,%u): expected %04x, actual %04x\n",
                            *text, x + col, y + row, expected, actual);
                    exit(1);
                }
            }
    }
}
int main(void)
{
    test_init();
    test.aa = 0; /* Exact font comparison; AA screenshots are inspected separately. */
    /* Smallest offending layout: one quad followed by another quad batch.
     * The second batch must start at byte 32, with COUNT still equal to one. */
    test_quad(0, 0, 8, 16, 0, 128, 1, 255);
    test_draw(0, 0, 1, 0, 1, 0);
    unsigned first = test.quads_count;
    test_quad(8, 0, 8, 16, 8, 128, 1, 255);
    test_draw(0, first, 1, 0, 1, 0);
    if (first != 2 || test.draws[1].count != 1) {
        fprintf(stderr, "Second quad batch: expected first=2 count=1, actual first=%u count=%u\n",
                first, test.draws[1].count);
        return 1;
    }
    for (unsigned scene = 1; scene <= 2; ++scene)
        for (unsigned mode = 0; mode < 3; ++mode)
            for (unsigned filter = 0; filter < (scene == 2 && mode == 2 ? 3u : 1u);
                 ++filter) {
                test_select(scene, mode, 6, filter);
                for (unsigned tick = 0; tick < 2; ++tick) {
                    test_frame();
                    for (unsigned i = 0; i < test.draws_count; ++i) {
                        const struct test_draw *draw = &test.draws[i];
                        if (draw->kind == 0 && (draw->first & 1)) {
                            fprintf(stderr, "Unaligned quad batch %u starts at %u\n",
                                    i, draw->first);
                            return 1;
                        }
                    }
                    text_pixels(8, 340, "NEXT/PREV MOVE  ENTER: CONTROLS  ESC: MENU", 0xffff);
                    if (scene == 2 && mode == 2) {
                        static const char *filters[] = {"NEAREST", "BILINEAR", "TRILINEAR"};
                        text_pixels(520, 56, filters[filter], 0xffff);
                        text_pixels(168, 288, "PERSPECTIVE / 7 MIP LEVELS", 0xffa5);
                    } else if (scene == 2) text_pixels(520, 56, "FLY THRU", 0xffff);
                }
            }
    pc_soc_destroy();
    puts("PASS aligned quad batches and complete HUD pixels in all modes");
    return 0;
}
