/* page_process.c — showcase design 4.6.2; full-screen L0 and L1 parameter panel.
 * Sliders accept pointer input; paired buttons support keys and encoder focus.
 */
#include "theme.h"
#include <stddef.h>
static bool collapsed;
static lv_obj_t *panel;
static lv_obj_t *view_label;
static lv_obj_t *values[15];
static lv_obj_t *sliders[15];
struct parameter { const char *name; size_t offset; int min, max, step; };
#define PARAM(name, field, low, high, step) {name, offsetof(ui_process_config_t, field), low, high, step}
static const struct parameter parameters[] = {
    PARAM("亮度", brightness, -256, 255, 1),
    PARAM("对比度 Q8", contrast, 0, 511, 8),
    PARAM("伽马 ×10", gamma_tenths, 3, 30, 1),
    PARAM("S1", stage1, 0, 6, 1), PARAM("S2", stage2, 0, 6, 1),
    PARAM("灰度", gray, 0, 1, 1), PARAM("二值化", binary, 0, 1, 1),
    PARAM("阈值", threshold, 0, 255, 1), PARAM("反色", invert, 0, 1, 1),
    PARAM("旋转角度", angle, -180, 180, 1),
    PARAM("缩放 %", scale_percent, 50, 400, 5),
    PARAM("平移 X", translate_x, -1280, 1280, 10),
    PARAM("平移 Y", translate_y, -720, 720, 10),
    PARAM("水平镜像", mirror_x, 0, 1, 1), PARAM("垂直镜像", mirror_y, 0, 1, 1)
};
static int *field(ui_process_config_t *config, unsigned i)
{
    return (int *)((char *)config + parameters[i].offset);
}
void ui_process_update(void)
{
    (void)ui_data_process(0);
    ui_process_config_t config = ui_data_process_config();
    ui_text(view_label, config.original ? "正在显示：原图" : "正在显示：处理后");
    const char *ops[] = {"旁路", "均值", "高斯", "锐化", "Sobel", "腐蚀", "膨胀"};
    for (unsigned i = 0; i < 15; ++i) {
        int value = *field(&config, i);
        char text[80];
        if (i == 3 || i == 4) lv_snprintf(text, sizeof text, "%s · %s", parameters[i].name,
                                         ops[value]);
        else if (i == 1) lv_snprintf(text, sizeof text, "对比度  %d.%02d", value/256,
                                     value%256*100/256);
        else if (i == 2) lv_snprintf(text, sizeof text, "伽马  %d.%d", value/10, value%10);
        else if (i == 5 || i == 6 || i == 8 || i >= 13)
            lv_snprintf(text, sizeof text, "%s  %s", parameters[i].name, value ? "开" : "关");
        else lv_snprintf(text, sizeof text, "%s  %d", parameters[i].name, value);
        ui_text(values[i], text);
        if (lv_slider_get_value(sliders[i]) != value)
            lv_slider_set_value(sliders[i], value, LV_ANIM_OFF);
    }
}
static void slider_changed(lv_event_t *event)
{
    unsigned i = (unsigned)(uintptr_t)lv_event_get_user_data(event);
    ui_process_config_t config = ui_data_process_config();
    *field(&config, i) = lv_slider_get_value(lv_event_get_target_obj(event));
    ui_data_process_set(&config);
    ui_process_update();
}
void ui_process_action(unsigned action)
{
    if (action == 0) { collapsed = !collapsed; ui_open(3); return; }
    ui_process_config_t config = ui_data_process_config();
    if (action == 1) config.original = !config.original;
    else if (action == 2) { ui_data_process_defaults(); ui_process_update(); return; }
    else {
        unsigned i = (action - 10) / 2;
        const struct parameter *p = &parameters[i];
        int value = *field(&config, i) + ((action & 1) ? p->step : -p->step);
        if (value < p->min) value = p->min;
        if (value > p->max) value = p->max;
        *field(&config, i) = value;
    }
    ui_data_process_set(&config);
    ui_process_update();
}
void ui_page_process(lv_obj_t *p)
{
    ui_video_surface(p);
    ui_label(p, "图像处理", 24, 12, &sim_font_28, TEXT);
    ui_button(p, collapsed ? "展开参数" : "收起参数", 730, 6, 160, 0);
    ui_button(p, "原图 / 处理后", 906, 6, 180, 1);
    view_label = lv_obj_get_child(lv_obj_get_child(p, -1), 0);
    ui_button(p, "恢复默认", 1102, 6, 162, 2);
    panel = ui_box(p, 920, 62, 344, 548, PANEL);
    lv_obj_set_style_bg_opa(panel, LV_OPA_80, 0);
    lv_obj_set_scrollable(panel, true);
    lv_obj_set_scroll_dir(panel, LV_DIR_VER);
    for (unsigned i = 0; i < 15; ++i) {
        int y = 18 + (int)i * 90;
        values[i] = ui_label(panel, "", 20, y, &sim_font_16, TEXT);
        ui_button(panel, "−", 20, y + 30, 42, 10 + 2*i);
        ui_button(panel, "+", 282, y + 30, 42, 11 + 2*i);
        sliders[i] = lv_slider_create(panel);
        lv_obj_set_pos(sliders[i], 80, y + 47);
        lv_obj_set_size(sliders[i], 184, 8);
        lv_obj_set_style_bg_color(sliders[i], lv_color_hex(LINE), LV_PART_MAIN);
        lv_obj_set_style_bg_opa(sliders[i], LV_OPA_COVER, LV_PART_MAIN);
        lv_obj_set_style_radius(sliders[i], 4, LV_PART_MAIN);
        lv_obj_set_style_bg_color(sliders[i], lv_color_hex(ACCENT), LV_PART_INDICATOR);
        lv_obj_set_style_bg_opa(sliders[i], LV_OPA_COVER, LV_PART_INDICATOR);
        lv_obj_set_style_bg_color(sliders[i], lv_color_hex(ACCENT), LV_PART_KNOB);
        lv_obj_set_style_bg_opa(sliders[i], LV_OPA_COVER, LV_PART_KNOB);
        lv_obj_set_style_radius(sliders[i], LV_RADIUS_CIRCLE, LV_PART_KNOB);
        lv_obj_set_style_pad_all(sliders[i], 5, LV_PART_KNOB);
        lv_slider_set_range(sliders[i], parameters[i].min, parameters[i].max);
        lv_obj_add_event_cb(sliders[i], slider_changed, LV_EVENT_VALUE_CHANGED,
                            (void *)(uintptr_t)i);
    }
    lv_obj_set_hidden(panel, collapsed);
}
