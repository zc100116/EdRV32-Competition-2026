/* page_settings.c — R4 design §4/5; LVGL menu, immediate runtime settings.
 * GUI clock; camera SCCB requests use the existing asynchronous data interface.
 */
#include "widgets.h"
#include "grab.h"
#include "../board/vision/metrics.h"
#include <stdio.h>
/* R4 explicitly requires lv_menu, deprecated in the locked LVGL 9.6 API. */
LV_DEPRECATIONS_IGNORE_BEGIN
bool ui_debug_overlay;
static unsigned mode;
static int thresholds[] = {25,35,0,25};
static bool keypoints;
static lv_obj_t *threshold;
static lv_obj_t *threshold_caption;
void ui_settings_apply_grab(void)
{
    ui_grab.mode = mode;
    for (unsigned i = 0; i < 4; ++i) ui_grab.thresholds[i] = thresholds[i];
    ui_grab.keypoints = keypoints;
}
static void param_output(void)
{
    char text[96];
    int value = thresholds[mode];
    if (mode < 2)
        snprintf(text,sizeof text,"grab param mode=%c value=%s%d.%02d\r\n",
                 'A'+mode,value < 0 ? "-" : "",LV_ABS(value)/100,LV_ABS(value)%100);
    else if (mode == 2) snprintf(text,sizeof text,"grab param mode=C value=none\r\n");
    else snprintf(text,sizeof text,"grab param mode=D value=%d\r\n",value);
    ui_data_grab_output(text);
}
static void threshold_sync(void)
{
    lv_spinbox_set_digit_format(threshold,3,mode < 2 ? 1 : 0);
    lv_spinbox_set_value(threshold,thresholds[mode]);
    lv_obj_t *row = lv_obj_get_parent(threshold);
    for (unsigned i = 1; i < lv_obj_get_child_count(row); ++i) {
        lv_obj_t *control = lv_obj_get_child(row,(int)i);
        if (mode == 2) lv_obj_add_state(control,LV_STATE_DISABLED);
        else lv_obj_remove_state(control,LV_STATE_DISABLED);
    }
    lv_label_set_text(threshold_caption,mode < 2 ? "阈值 · 比例" :
                      mode == 2 ? "模式 C 无阈值" : "阈值 · 像素");
}
static void threshold_changed(lv_event_t *event);
static void mode_changed(lv_event_t *event)
{
    mode = lv_buttonmatrix_get_selected_button(lv_event_get_target_obj(event));
    ui_grab.pending_frames = 0;
    ui_grab.smooth = false;
    ui_settings_apply_grab();
    /* Changing the displayed mode is not a threshold edit. */
    lv_obj_remove_event_cb(threshold,threshold_changed);
    threshold_sync();
    lv_obj_add_event_cb(threshold,threshold_changed,LV_EVENT_VALUE_CHANGED,NULL);
    param_output();
}
static void threshold_changed(lv_event_t *event)
{
    thresholds[mode] = lv_spinbox_get_value(lv_event_get_target_obj(event));
    ui_settings_apply_grab();
    ui_grab.pending_frames = 0;
    param_output();
}
static void switch_changed(lv_event_t *event)
{
    unsigned setting = (unsigned)(uintptr_t)lv_event_get_user_data(event);
    bool checked = lv_obj_has_state(lv_event_get_target_obj(event),LV_STATE_CHECKED);
    if (setting == 0) {
        ui_grab.mirror = checked;
        ui_data_grab_mirror(checked);
        ui_data_grab_output(checked ? "grab mirror=1\r\n" : "grab mirror=0\r\n");
    } else if (setting == 1) {
        if (checked != ui_monitor_visible()) ui_monitor_toggle();
    } else if (setting == 3) {
        ui_debug_overlay = checked;
    } else {
        keypoints = checked;
        ui_grab.keypoints = checked;
        ui_data_grab_output(checked ? "grab keypoints=1\r\n" : "grab keypoints=0\r\n");
    }
}
static void exposure_changed(lv_event_t *event)
{
    bool short_exposure = lv_buttonmatrix_get_selected_button(lv_event_get_target_obj(event)) == 1;
    if (short_exposure != ui_data_exposure_short()) ui_data_exposure_toggle();
}
static void switch_setting(lv_obj_t *parent, const char *name, bool value, unsigned id)
{
    lv_obj_t *o = ui_switch_row(parent,name,value);
    lv_obj_add_event_cb(o,switch_changed,LV_EVENT_VALUE_CHANGED,(void *)(uintptr_t)id);
}
static lv_obj_t *section(lv_obj_t *page, const char *name, int width)
{
    lv_obj_t *o = lv_menu_section_create(page);
    lv_obj_set_width(o,LV_PCT(width));
    lv_obj_set_style_pad_all(o,UI_SPACE_LG,0);
    lv_obj_set_style_pad_gap(o,UI_SPACE_SM,0);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0);
    lv_obj_set_style_bg_color(o,lv_color_hex(PANEL),0);
    lv_obj_set_style_radius(o,UI_RADIUS_LG,0);
    ui_emphasis(o,name,false);
    return o;
}
static void grab_test(lv_event_t *event)
{ (void)event; ui_open(14); }
void ui_page_settings(lv_obj_t *parent)
{
    lv_obj_set_flex_flow(parent,LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_all(parent,UI_SPACE_LG,0);
    lv_obj_set_style_pad_gap(parent,UI_SPACE_MD,0);
    lv_obj_t *heading = ui_stack(parent,LV_FLEX_FLOW_ROW,UI_SPACE_LG);
    lv_obj_set_flex_align(heading,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    ui_emphasis(heading,"设置",true);
    ui_badge(heading,"即时生效 · 本次运行保留");
    lv_obj_t *menu = lv_menu_create(parent);
    lv_obj_set_width(menu,LV_PCT(100));
    lv_obj_set_flex_grow(menu,1);
    lv_obj_t *page = lv_menu_page_create(menu,NULL);
    lv_obj_set_flex_flow(page,LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(page,LV_FLEX_ALIGN_SPACE_BETWEEN,LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_START);
    lv_obj_set_style_pad_all(page,UI_SPACE_SM,0);
    lv_obj_t *display = section(page,"显示",36);
    switch_setting(display,"镜像",ui_grab.mirror,0);
    switch_setting(display,"性能窗",ui_monitor_visible(),1);
    switch_setting(display,"调试叠加",ui_debug_overlay,3);
    ui_text_label(display,"摄像头显示与运行指标",&sim_font_16,MUTED);
    lv_obj_t *grab = section(page,"抓取判定",62);
    ui_text_label(grab,"模式",&sim_font_20,TEXT);
    static const char *const modes[] = {"A","B","C","D",""};
    lv_obj_t *selector = ui_segment(grab,modes,mode);
    lv_obj_set_width(selector,LV_PCT(100));
    lv_obj_add_event_cb(selector,mode_changed,LV_EVENT_VALUE_CHANGED,NULL);
    threshold = ui_number_row(grab,"阈值",thresholds[mode]);
    threshold_caption = lv_obj_get_child(lv_obj_get_parent(threshold),0);
    threshold_sync();
    lv_obj_add_event_cb(threshold,threshold_changed,LV_EVENT_VALUE_CHANGED,NULL);
    switch_setting(grab,"关键点显示",keypoints,2);
    ui_text_label(grab,"曝光",&sim_font_20,TEXT);
    static const char *const exposures[] = {"标准","短",""};
    selector = ui_segment(grab,exposures,ui_data_exposure_short() ? 1 : 0);
    lv_obj_set_width(selector,LV_PCT(100));
    lv_obj_add_event_cb(selector,exposure_changed,LV_EVENT_VALUE_CHANGED,NULL);
    lv_obj_t *test = lv_button_create(grab);
    ui_widget_style(test);
    lv_obj_set_flex_flow(test,LV_FLEX_FLOW_ROW);
    ui_text_label(test,"抓取测试",&sim_font_16,TEXT);
    ui_control(test);
    lv_obj_add_event_cb(test,grab_test,LV_EVENT_CLICKED,NULL);
    lv_menu_set_page(menu,page);
    ui_hint("确认：切换开关 / 进入参数编辑    下一个 / 上一个：选择或调节    返回：退出编辑");
}

LV_DEPRECATIONS_IGNORE_END
