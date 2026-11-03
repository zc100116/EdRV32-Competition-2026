/* theme.c — showcase design §3/4.1; B light theme initialized once.
 * Opaque rectangles and glyphs only; UI thread, LVGL tick clock.
 */
#include "theme.h"
static lv_style_t panel_style;
static lv_style_t focus_style;
static lv_style_t label_style;
void theme_init(void)
{
    lv_style_init(&panel_style);
    lv_style_set_bg_opa(&panel_style, LV_OPA_COVER);
    lv_style_set_bg_color(&panel_style, lv_color_hex(PANEL));
    lv_style_set_border_color(&panel_style, lv_color_hex(LINE));
    lv_style_set_border_width(&panel_style, 1);
    lv_style_set_radius(&panel_style, 12);
    lv_style_init(&focus_style);
    lv_style_set_bg_color(&focus_style, lv_color_hex(SELECTED));
    lv_style_set_border_color(&focus_style, lv_color_hex(ACCENT));
    lv_style_set_border_width(&focus_style, 2);
    lv_style_init(&label_style);
    lv_style_set_text_font(&label_style, &sim_font_16);
    lv_style_set_text_color(&label_style, lv_color_hex(TEXT));
}
lv_obj_t *ui_box(lv_obj_t *p, int x, int y, int w, int h, uint32_t color)
{
    lv_obj_t *o = lv_obj_create(p);
    lv_obj_remove_style_all(o);
    lv_obj_add_style(o, &panel_style, 0);
    lv_obj_add_style(o, &focus_style, LV_STATE_FOCUSED);
    lv_obj_set_style_bg_color(o, lv_color_hex(color), 0);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, h);
    lv_obj_set_scrollable(o, false);
    lv_obj_set_clickable(o, false);
    return o;
}
lv_obj_t *ui_label(lv_obj_t *p, const char *s, int x, int y,
                   const lv_font_t *font, uint32_t color)
{
    lv_obj_t *o = lv_label_create(p);
    lv_obj_remove_style_all(o);
    lv_obj_add_style(o, &label_style, 0);
    lv_obj_set_style_text_font(o, font, 0);
    lv_obj_set_style_text_color(o, lv_color_hex(color), 0);
    lv_label_set_text(o, s);
    lv_obj_set_pos(o, x, y);
    return o;
}
void ui_text(lv_obj_t *o, const char *text)
{
    if(lv_strcmp(lv_label_get_text(o), text)) lv_label_set_text(o, text);
}
void ui_bar(lv_obj_t *p, int x, int y, int w, int value, uint32_t color)
{
    lv_obj_t *o = ui_box(p, x, y, w, 8, LINE);
    lv_obj_set_style_border_width(o, 0, 0);
    o = ui_box(p, x, y, value, 8, color);
    lv_obj_set_style_border_width(o, 0, 0);
}
void ui_picture(lv_obj_t *p, const lv_image_dsc_t *src, int x, int y, int w, int h)
{
    lv_obj_t *o = lv_image_create(p);
    lv_image_set_src(o, src);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, h);
    lv_image_set_inner_align(o, LV_IMAGE_ALIGN_STRETCH);
}
void ui_title(lv_obj_t *p, const char *title)
{
    ui_label(p, title, 40, 20, &sim_font_40, TEXT);
}

void ui_video_surface(lv_obj_t *p)
{
    lv_obj_t *screen = lv_obj_get_parent(p);
    lv_obj_set_style_bg_opa(screen, LV_OPA_TRANSP, 0);
    lv_obj_set_style_bg_opa(p, LV_OPA_TRANSP, 0);
    lv_obj_t *header = ui_box(p, 0, 0, 1280, 48, PANEL);
    lv_obj_set_style_bg_opa(header, LV_OPA_80, 0);
    lv_obj_set_style_radius(header, 0, 0);
    lv_obj_set_style_border_width(header, 0, 0);
    for (unsigned i = 0; i < lv_obj_get_child_count(screen); ++i) {
        lv_obj_t *child = lv_obj_get_child(screen, (int)i);
        if (child != p) lv_obj_set_style_bg_opa(child, LV_OPA_80, 0);
    }
}
