/* File: ui.h
 * Spec: ember_isles E1/E2; gdd 3-5; GPU 2.8.
 * Description: Native Chinese HUD, menus and item panels; CPU quad builders.
 * Clock domain: CPU frame.
 */
#ifndef EMBER_UI_H
#define EMBER_UI_H
#include "gpu.h"
#include "sim/sim.h"
enum { EMBER_UI_RECTS = 384, EMBER_UI_GLYPHS = 2048 };
enum ember_ui_color { EMBER_TRUE = 0, EMBER_MIXED = 1, EMBER_PANEL = 2, EMBER_EDGE, EMBER_FIRE, EMBER_TIDE,
                      EMBER_PAPER, EMBER_HEALTH, EMBER_TRACK, EMBER_SHADE, EMBER_STAR, EMBER_SHADOW };
enum ember_menu_page { EMBER_TITLE, EMBER_WEAPON_MENU, EMBER_SETTINGS };
struct ember_ui_state { unsigned show_perf, tick_rate, menu_page, menu_selected, volume; };
struct ember_ui_canvas {
    struct gpu_quad *rects;
    struct gpu_quad *glyphs;
    unsigned rect_count;
    unsigned glyph_count;
    uint32_t codepoints[EMBER_UI_GLYPHS];
};
void ember_ui_text(struct ember_ui_canvas *out, int x, int y, const char *text, unsigned big);
void ember_ui_build(struct ember_ui_canvas *out, const struct ember_sim *sim,
                    const struct ember_ui_state *state, unsigned fps, const uint32_t *perf,
                    unsigned particles);
#endif
