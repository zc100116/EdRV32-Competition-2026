/* theme.c — showcase design §3/4.1; B light theme initialized once.
 * Session reason glyphs (P5 8.1): 长度不符、格式错误、空间不足、硬件不支持、状态不符、已取消。
 * Opaque rectangles and glyphs only; UI thread, LVGL tick clock.
 */
#include "theme.h"
static lv_style_t panel_style;
static lv_style_t focus_style;
static lv_style_t label_style;
static lv_style_t hover_style, pressed_style, checked_style, disabled_style;
void theme_init(void)
{
    lv_style_init(&panel_style);
    lv_style_set_bg_opa(&panel_style, LV_OPA_COVER);
    lv_style_set_bg_color(&panel_style, lv_color_hex(PANEL));
    lv_style_set_border_color(&panel_style, lv_color_hex(LINE));
    lv_style_set_border_width(&panel_style, 1);
    lv_style_set_radius(&panel_style, 12);
    lv_style_init(&focus_style);
    lv_style_set_outline_color(&focus_style, lv_color_hex(ACCENT));
    lv_style_set_outline_width(&focus_style, 3);
    lv_style_set_outline_pad(&focus_style, 3);
    lv_style_set_border_color(&focus_style, lv_color_hex(ACCENT));
    lv_style_set_border_width(&focus_style, 2);
    lv_style_init(&hover_style);
    lv_style_set_bg_color(&hover_style, lv_color_hex(0xf0f6ff));
    lv_style_set_border_color(&hover_style, lv_color_hex(0x93b4f5));
    lv_style_init(&pressed_style);
    lv_style_set_bg_color(&pressed_style, lv_color_hex(0xc9dcff));
    lv_style_set_border_color(&pressed_style, lv_color_hex(ACCENT));
    lv_style_init(&checked_style);
    lv_style_set_bg_color(&checked_style, lv_color_hex(0xd9f2ed));
    lv_style_set_border_color(&checked_style, lv_color_hex(TEAL));
    lv_style_init(&disabled_style);
    lv_style_set_bg_color(&disabled_style, lv_color_hex(DISABLED));
    lv_style_set_text_color(&disabled_style, lv_color_hex(MUTED));
    lv_style_set_opa(&disabled_style, LV_OPA_60);
    lv_style_init(&label_style);
    lv_style_set_text_font(&label_style, &sim_font_16);
    lv_style_set_text_color(&label_style, lv_color_hex(TEXT));
}
lv_obj_t *ui_box(lv_obj_t *p, int x, int y, int w, int h, uint32_t color)
{
    lv_obj_t *o = lv_obj_create(p);
    lv_obj_remove_style_all(o);
    lv_obj_add_style(o, &panel_style, 0);

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

void ui_control_style(lv_obj_t *o)
{
    lv_obj_remove_style_all(o);
    lv_obj_add_style(o, &panel_style, 0);
    lv_obj_add_style(o, &label_style, 0);
    lv_obj_add_style(o, &hover_style, LV_STATE_HOVERED);
    lv_obj_add_style(o, &checked_style, LV_STATE_CHECKED);
    lv_obj_add_style(o, &pressed_style, LV_STATE_PRESSED);
    lv_obj_add_style(o, &disabled_style, LV_STATE_DISABLED);
    lv_obj_add_style(o, &focus_style, LV_STATE_FOCUS_KEY);
    lv_obj_set_style_outline_color(o,lv_color_hex(TEAL),LV_STATE_EDITED);
    lv_obj_set_scrollable(o, false);
}
lv_obj_t *ui_switch(lv_obj_t *p, int x, int y)
{
    lv_obj_t *o=lv_switch_create(p);
    ui_control_style(o);
    lv_obj_set_pos(o,x,y); lv_obj_set_size(o,44,24);
    lv_obj_set_style_radius(o,LV_RADIUS_CIRCLE,0);
    lv_obj_set_style_bg_color(o,lv_color_hex(0x94a3b8),0);
    lv_obj_set_style_bg_color(o,lv_color_hex(TEAL),LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,LV_PART_INDICATOR | LV_STATE_CHECKED);
    lv_obj_set_style_radius(o,LV_RADIUS_CIRCLE,LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(o,lv_color_hex(PANEL),LV_PART_KNOB);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,LV_PART_KNOB);
    lv_obj_set_style_pad_all(o,-3,LV_PART_KNOB);
    lv_obj_set_style_radius(o,LV_RADIUS_CIRCLE,LV_PART_KNOB);
    ui_control(o); return o;
}
lv_obj_t *ui_slider(lv_obj_t *p,int x,int y,int w,int low,int high)
{
    lv_obj_t *o=lv_slider_create(p); ui_control_style(o);
    lv_obj_set_pos(o,x,y); lv_obj_set_size(o,w,8);
    lv_slider_set_range(o,low,high);
    lv_obj_set_style_bg_color(o,lv_color_hex(LINE),0);
    lv_obj_set_style_bg_color(o,lv_color_hex(ACCENT),LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(o,lv_color_hex(ACCENT),LV_PART_KNOB);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,LV_PART_KNOB);
    lv_obj_set_style_radius(o,LV_RADIUS_CIRCLE,LV_PART_KNOB);
    lv_obj_set_style_pad_all(o,6,LV_PART_KNOB);
    ui_control(o); return o;
}
lv_obj_t *ui_dropdown(lv_obj_t *p,int x,int y,int w,const char *options)
{
    lv_obj_t *o=lv_dropdown_create(p); ui_control_style(o);
    lv_obj_set_pos(o,x,y); lv_obj_set_size(o,w,36);
    lv_obj_set_style_pad_all(o,7,0);
    lv_dropdown_set_options(o,options);
    lv_dropdown_set_symbol(o,LV_SYMBOL_DOWN);
    lv_obj_t *list=lv_dropdown_get_list(o); ui_control_style(list);
    lv_obj_set_style_pad_all(list,8,LV_PART_SELECTED);
    lv_obj_set_style_bg_color(list,lv_color_hex(SELECTED),LV_PART_SELECTED);
    lv_obj_set_style_bg_opa(list,LV_OPA_COVER,LV_PART_SELECTED);
    lv_obj_set_scrollable(list,true); lv_obj_set_style_max_height(list,220,0);
    ui_control(o); return o;
}
