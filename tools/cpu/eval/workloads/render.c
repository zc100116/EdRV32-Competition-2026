/* render.c — cpu-spec 4.1–4.4 evaluation; LVGL software framebuffer.
 * Label, button and list: first render warms state, then measure one scroll frame.
 * CPU/Spike domain; no display controller or accelerator.
 */
#include "lvgl.h"
extern void start_time(void);
extern void stop_time(void);
static uint16_t framebuffer[160 * 120];
volatile unsigned result;

static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    (void)area;
    (void)pixels;
    lv_display_flush_ready(display);
}

int main(void)
{
    lv_init();
    lv_display_t *display = lv_display_create(160, 120);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(display, framebuffer, NULL, sizeof framebuffer,
                           LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(display, flush);
    lv_theme_t *theme = lv_theme_simple_init(display);
    lv_display_set_theme(display, theme);
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *label = lv_label_create(screen);
    lv_label_set_text(label, "Vision status");
    lv_obj_set_pos(label, 2, 2);
    lv_obj_t *button = lv_button_create(screen);
    lv_obj_set_pos(button, 100, 1);
    lv_obj_set_size(button, 58, 24);
    lv_label_set_text(lv_label_create(button), "Run");
    lv_obj_t *list = lv_obj_create(screen);
    lv_obj_set_flex_flow(list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_pos(list, 0, 28);
    lv_obj_set_size(list, 160, 92);
    for (unsigned i = 0; i < 8; ++i) {
        lv_obj_t *row = lv_button_create(list);
        lv_obj_set_width(row, LV_PCT(100));
        lv_label_set_text(lv_label_create(row), "Object detected");
    }
    lv_refr_now(display);
    lv_obj_scroll_to_y(list, 24, LV_ANIM_OFF);
    lv_obj_invalidate(screen);
    start_time();
    lv_refr_now(display);
    stop_time();
    result = framebuffer[160 * 60 + 80];
    return 0;
}
