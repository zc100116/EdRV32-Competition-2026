/* File: ui.h
 * Spec: ember_isles E1/E2; gdd 3-5; GPU 2.8.
 * Description: CPU-only HUD, menu and upgrade quad builders.
 * Clock domain: CPU frame.
 */
#ifndef EMBER_UI_H
#define EMBER_UI_H
#include "gpu.h"
#include "sim/sim.h"
enum { EMBER_UI_RECTS = 96, EMBER_UI_GLYPHS = 2048 };
enum ember_ui_color { EMBER_PANEL = 2, EMBER_EDGE, EMBER_FIRE, EMBER_TIDE,
                      EMBER_PAPER, EMBER_HEALTH, EMBER_TRACK, EMBER_SHADE };
struct ember_ui_state { unsigned show_perf; unsigned tick_rate; };
struct ember_ui_canvas {
    struct gpu_quad *rects;
    struct gpu_quad *glyphs;
    unsigned rect_count;
    unsigned glyph_count;
};
void ember_ui_text(struct ember_ui_canvas *out, int x, int y, const char *text, unsigned big);
void ember_ui_build(struct ember_ui_canvas *out, const struct ember_sim *sim,
                    const struct ember_ui_state *state, unsigned fps, const uint32_t *perf,
                    unsigned particles);
#endif
