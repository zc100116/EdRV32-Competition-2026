/* renderer.h — RND spec 2.1–2.6 / showcase 4.6.3; paired renderer fixtures.
 * LVGL software draws into offscreen memory; board backend submits RND commands.
 */
#ifndef SHOWCASE_RENDERER_H
#define SHOWCASE_RENDERER_H
#include "lvgl.h"
enum { RENDER_W=192, RENDER_H=96, RENDER_SW=64, RENDER_SH=32 };
enum {
    TEST_FILL, TEST_ALPHA, TEST_GRAD_H, TEST_GRAD_V, TEST_ROUND, TEST_BORDER,
    TEST_A8, TEST_A4, TEST_A2, TEST_A1, TEST_RGB565, TEST_ARGB8888,
    TEST_SCALE, TEST_FLIP, TEST_RECOLOR, TEST_KEY, TEST_I8, TEST_COPY,
    TEST_COPY_ARGB, TEST_FILL_ARGB, TEST_ALPHA_ARGB, TEST_BLIT_ARGB_TARGET,
    TEST_LAYERS, RENDER_TEST_COUNT
};
static inline unsigned ui_render_kind(unsigned test)
{
    return test==TEST_FILL_ARGB ? TEST_FILL : test==TEST_ALPHA_ARGB ? TEST_ALPHA :
        test==TEST_BLIT_ARGB_TARGET ? TEST_ARGB8888 : test;
}
typedef struct {
    const char *name;
    unsigned hardware_us, software_us, equal, total;
    bool complete;
} ui_render_result_t;
extern const char *const ui_render_names[RENDER_TEST_COUNT];
/* The packed source and palette remain alive through synchronous RND completion. */
void ui_render_source(unsigned test);
const lv_image_dsc_t *ui_render_source_image(void);
const uint32_t *ui_render_palette(void);
void ui_render_clear(unsigned test,void *pixels);
void ui_render_software(unsigned test,void *pixels);
lv_color_format_t ui_render_format(unsigned test);
unsigned ui_render_bytes(unsigned test);
const ui_render_result_t *ui_data_render_results(void);
void ui_data_render_start(unsigned test); /* RENDER_TEST_COUNT runs all drawing items. */
bool ui_data_render_running(void);
const lv_image_dsc_t *ui_data_render_image(unsigned side);
void ui_graphics_action(unsigned action);
#endif
