/* live_demo.c — live demo L1/L9/L10; reuse existing scenes and global preprocessing.
 * GUI task owns directory focus, banner and scene navigation.
 */
#include "live_demo.h"
#include "motion.h"
static const struct {
    unsigned chapter, page;
    const char *name;
} scenes[] = {
    {1,1,"目标检测（80 类）"}, {1,10,"手势识别"}, {1,9,"人体姿态"},
    {2,13,"安全帽检测"}, {2,19,"智慧农场"}, {3,3,"图像处理"}, {4,4,"图形引擎"},
    {5,18,"抓取实验"}, {5,15,"弹弓打靶"},
    {6,7,"CoreMark 跑分"}, {6,5,"NES 经典游戏"}
};
static const char *const chapters[] = {
    "", "自研 NPU · 多模型部署", "落地应用", "自研图像处理", "自研渲染器", "体感交互", "自研 CPU · 跑分与经典游戏"
};
static const char *const presets[] = {"原始", "暗光增强", "降噪", "暗光增强+降噪"};
static unsigned scene, selected, current;
static lv_obj_t *summary, *tag, *preset_control;
static unsigned preset_page;
static unsigned tag_page;
static lv_obj_t *advanced, *parameters[7], *values[4];
static unsigned advanced_page;
void ui_preprocess_reset(void) { tag = advanced = preset_control = NULL; }
static void advanced_refresh(void)
{
    if (!advanced || advanced_page != ui_page) return;
    ui_preprocess_t d = ui_data_preprocess();
    int data[] = {d.brightness,d.contrast,d.gamma_tenths,d.exposure};
    for (unsigned i = 0; i < 4; ++i) {
        char text[40];
        if (i == 1) lv_snprintf(text,sizeof text,"%d.%02d",data[i]/256,data[i]%256*100/256);
        else if (i == 2) lv_snprintf(text,sizeof text,"%d.%d",data[i]/10,data[i]%10);
        else lv_snprintf(text,sizeof text,"%d",data[i]);
        ui_text(values[i],text);
        lv_slider_set_value(parameters[i],data[i],LV_ANIM_OFF);
        bool disabled = i < 3 && (!(ui_data_hardware() & UI_PIX) ||
            (i < 2 ? d.auto_levels : d.auto_gamma));
        lv_obj_set_state(parameters[i],LV_STATE_DISABLED,disabled);
    }
    lv_obj_set_state(parameters[4],LV_STATE_CHECKED,d.auto_levels);
    lv_obj_set_state(parameters[5],LV_STATE_CHECKED,d.auto_gamma);
}
static void advanced_changed(lv_event_t *e)
{
    unsigned id = (unsigned)(uintptr_t)lv_event_get_user_data(e);
    lv_obj_t *o = lv_event_get_target_obj(e);
    ui_preprocess_t d = ui_data_preprocess();
    if (id == 0) d.brightness = lv_slider_get_value(o);
    if (id == 1) d.contrast = lv_slider_get_value(o);
    if (id == 2) d.gamma_tenths = lv_slider_get_value(o);
    if (id == 3) d.exposure = lv_slider_get_value(o);
    if (id == 4) d.auto_levels = lv_obj_has_state(o,LV_STATE_CHECKED);
    if (id == 5) d.auto_gamma = lv_obj_has_state(o,LV_STATE_CHECKED);
    if (id == 6) d.filter = lv_dropdown_get_selected(o);
    ui_data_preprocess_custom(&d);
    ui_preprocess_refresh();
}
void ui_preprocess_advanced(lv_obj_t *parent)
{
    advanced = parent; advanced_page = ui_page;
    ui_text_label(parent,"高级",&sim_font_20,ACCENT);
    ui_preprocess_t d = ui_data_preprocess();
    parameters[4] = ui_flex_switch(parent,"自动色阶",d.auto_levels);
    parameters[5] = ui_flex_switch(parent,"自动 gamma",d.auto_gamma);
    static const char *const names[] = {"亮度","对比度","gamma","传感器曝光目标"};
    static const int low[] = {-256,128,4,24}, high[] = {255,511,15,120};
    for (unsigned i = 0; i < 4; ++i) {
        lv_obj_t *row = ui_stack(parent,LV_FLEX_FLOW_ROW,8);
        lv_obj_set_width(row,LV_PCT(100));
        lv_obj_t *name = ui_text_label(row,names[i],&sim_font_16,TEXT);
        lv_obj_set_flex_grow(name,1);
        values[i] = ui_text_label(row,"",&sim_font_16,ACCENT);
        parameters[i] = lv_slider_create(parent);
        ui_widget_style(parameters[i]);
        lv_obj_set_size(parameters[i],LV_PCT(90),18);
        lv_obj_set_style_margin_bottom(parameters[i],10,0);
        lv_slider_set_range(parameters[i],low[i],high[i]);
        ui_control(parameters[i]);
    }
    ui_text_label(parent,"滤波",&sim_font_16,TEXT);
    parameters[6] = lv_dropdown_create(parent);
    ui_widget_style(parameters[6]);
    lv_dropdown_set_options(parameters[6],"无\n均值\n高斯\n锐化");
    lv_dropdown_set_selected(parameters[6],d.filter);
    lv_obj_set_width(parameters[6],LV_PCT(100));
    ui_control(parameters[6]);
    for (unsigned i = 0; i < 7; ++i) {
        lv_obj_add_event_cb(parameters[i],advanced_changed,LV_EVENT_VALUE_CHANGED,
                            (void *)(uintptr_t)i);
        if (!(ui_data_hardware() & UI_PIX) && i >= 4)
            lv_obj_add_state(parameters[i],LV_STATE_DISABLED);
    }
    advanced_refresh();
}
unsigned ui_live_scene(void) { return scene; }
void ui_live_exit(void) { scene = current = 0; }
static void preset_changed(lv_event_t *e)
{
    ui_data_preprocess_set(lv_buttonmatrix_get_selected_button(lv_event_get_target_obj(e)));
    ui_preprocess_refresh();
    if (ui_page == LIVE_DEMO_PAGE) ui_live_refresh();
}
void ui_preset_controls(lv_obj_t *parent)
{
    ui_text_label(parent,"识别前处理",&sim_font_20,TEXT);
    static const char *const map[] = {"原始","暗光增强","\n","降噪","增强+降噪",""};
    preset_page = ui_page;
    unsigned preset = ui_data_preprocess().preset;
    lv_obj_t *control = ui_segment(parent,map,
        preset == 255 ? LV_BUTTONMATRIX_BUTTON_NONE : preset);
    preset_control = control;
    lv_obj_set_size(control,LV_PCT(100),88);
    if (!(ui_data_hardware() & UI_PIX)) {
        for (unsigned i = 1; i <= 3; ++i)
            lv_buttonmatrix_set_button_ctrl(control,i,LV_BUTTONMATRIX_CTRL_DISABLED);
        ui_text_label(parent,"本 FPGA 版本无 PIX",&sim_font_14,MUTED);
    }
    lv_obj_add_event_cb(control,preset_changed,LV_EVENT_VALUE_CHANGED,NULL);
}
void ui_preprocess_tag(lv_obj_t *parent)
{
    tag_page = ui_page;
    tag = ui_label(parent,"",12,52,&sim_font_14,TEXT);
    lv_obj_set_ignore_layout(tag,true);
    lv_obj_set_style_bg_color(tag,lv_color_hex(PANEL),0);
    lv_obj_set_style_bg_opa(tag,LV_OPA_COVER,0);
    lv_obj_set_style_pad_all(tag,4,0);
    ui_preprocess_refresh();
}
void ui_preprocess_refresh(void)
{
    advanced_refresh();
    if (preset_control && preset_page == ui_page) {
        unsigned preset = ui_data_preprocess().preset;
        lv_buttonmatrix_clear_button_ctrl_all(preset_control,LV_BUTTONMATRIX_CTRL_CHECKED);
        lv_buttonmatrix_set_selected_button(preset_control,
            preset == 255 ? LV_BUTTONMATRIX_BUTTON_NONE : preset);
        if (preset != 255)
            lv_buttonmatrix_set_button_ctrl(preset_control,preset,LV_BUTTONMATRIX_CTRL_CHECKED);
    }
    if (!tag || tag_page != ui_page) return;
    ui_preprocess_t d = ui_data_preprocess();
    char text[200];
    lv_snprintf(text,sizeof text,"前处理：%s · 亮度 %u · 色阶 %d/%d · γ %d.%d · 曝光 %d",
        d.preset == 255 ? "自定义" : presets[d.preset],d.luma,d.contrast,d.brightness,
        d.gamma_tenths/10,d.gamma_tenths%10,d.exposure);
    ui_text(tag,text);
}
void ui_live_command(unsigned action, unsigned arg)
{
    if (action == 3) { ui_data_preprocess_set(arg); return; }
    if (action == 4) { scene = LIVE_DEMO_DIRECTORY; ui_open(LIVE_DEMO_PAGE); return; }
    if (action == 0) selected = arg-1;
    else selected = current ? current-1 : 0;
    if (action == 1) selected = current == 0 ? 0 : (selected+1)%11;
    if (action == 2) selected = current == 0 ? 10 : (selected+10)%11;
    current = scene = selected+1;
    ui_tab = ui_mode = 0;
    ui_detection_settings = false;
    if (selected == 8) ui_motion_entry = MOTION_SLING;
    if(ui_page == scenes[selected].page && ui_data_session().state == UI_STATE_PAUSED)
        ui_data_app_pause(false);
    ui_open(scenes[selected].page);
}
static void scene_clicked(lv_event_t *e)
{ ui_live_command(0,(unsigned)(uintptr_t)lv_event_get_user_data(e)+1); }
static void scene_focused(lv_event_t *e)
{ selected = (unsigned)(uintptr_t)lv_event_get_user_data(e); }
void ui_live_refresh(void)
{
    ui_preprocess_t d = ui_data_preprocess();
    char text[160];
    lv_snprintf(text,sizeof text,"识别前处理：%s    画面亮度：%u",
        d.preset == 255 ? "自定义" : presets[d.preset],d.luma);
    ui_text(summary,text);
}
void ui_live_directory(lv_obj_t *parent)
{
    lv_obj_set_flex_flow(parent,LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_all(parent,20,0);
    lv_obj_set_style_pad_gap(parent,10,0);
    summary = ui_text_label(parent,"",&sim_font_20,TEXT);
    lv_obj_t *rows = ui_stack(parent,LV_FLEX_FLOW_ROW,16);
    lv_obj_set_flex_grow(rows,1);
    lv_obj_set_width(rows,LV_PCT(100));
    lv_obj_t *focus = NULL;
    for (unsigned chapter = 1; chapter <= 6; ++chapter) {
        lv_obj_t *column = ui_panel(rows,190);
        lv_obj_set_height(column,LV_PCT(100));
        char title[120];
        const char *name = chapter==1 ? "自研 NPU\n多模型部署" :
            chapter==6 ? "自研 CPU\n跑分与经典游戏" : chapters[chapter];
        lv_snprintf(title,sizeof title,"第 %u 章\n%s",chapter,name);
        lv_obj_t *heading = ui_text_label(column,title,&sim_font_20,ACCENT);
        lv_obj_set_size(heading,LV_PCT(100),80);
        for (unsigned i = 0; i < 11; ++i) {
            if (scenes[i].chapter != chapter) continue;
            char text[120];
            lv_snprintf(text,sizeof text,"%u  %s%s",i+1,scenes[i].name,
                        i+1 == current ? " · 当前" : "");
            lv_obj_t *button = lv_button_create(column);
            ui_control_style(button);
            ui_control(button);
            lv_obj_t *label = ui_text_label(button,text,&sim_font_16,TEXT);
            lv_obj_set_width(label,LV_PCT(100));
            lv_obj_center(label);
            lv_obj_set_width(button,LV_PCT(100));
            lv_obj_set_height(button,80);
            lv_obj_add_event_cb(button,scene_clicked,LV_EVENT_CLICKED,(void *)(uintptr_t)i);
            lv_obj_add_event_cb(button,scene_focused,LV_EVENT_FOCUSED,(void *)(uintptr_t)i);
            if (i == selected) focus = button;
        }
    }
    lv_obj_t *controls = ui_stack(parent,LV_FLEX_FLOW_COLUMN,8);
    lv_obj_set_width(controls,600);
    ui_preset_controls(controls);
    lv_group_focus_obj(focus);
    lv_obj_add_state(focus,LV_STATE_FOCUS_KEY);
    ui_live_refresh();
}
void ui_live_banner(lv_obj_t *parent)
{
    char text[240];
    const unsigned i = scene-1;
    lv_snprintf(text,sizeof text,"现场演示 · 第 %u 章 %s · %s %u/11",
        scenes[i].chapter,chapters[scenes[i].chapter],scenes[i].name,scene);
    lv_obj_t *banner = ui_box(parent,0,0,1280,32,PANEL);
    lv_obj_set_clickable(banner,false);
    ui_label(banner,text,16,5,&sim_font_16,ACCENT);
}
bool ui_live_back(void)
{
    if (!scene) return false;
    if (scene == LIVE_DEMO_DIRECTORY) { scene = current = 0; ui_open(0); }
    else { selected = scene%11; scene = LIVE_DEMO_DIRECTORY; ui_open(LIVE_DEMO_PAGE); }
    return true;
}
