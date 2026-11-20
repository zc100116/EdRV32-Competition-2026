/* live_demo.c — live demo L1–L4; reuse existing scenes and global preprocessing.
 * GUI task owns directory focus, banner and scene navigation.
 */
#include "live_demo.h"
#include "motion.h"
static const struct {
    unsigned chapter, page;
    const char *name;
} scenes[] = {
    {1,1,"目标检测（80 类）"}, {1,10,"手势识别"}, {1,9,"人体姿态"},
    {2,13,"安全帽检测"}, {2,19,"智慧农场"}, {3,4,"图形引擎"},
    {4,18,"抓取实验"}, {4,15,"弹弓打靶"},
    {5,7,"CoreMark 跑分"}, {5,5,"NES 经典游戏"}
};
static const char *const chapters[] = {
    "", "自研 NPU · 多模型部署", "落地应用", "自研渲染器", "体感交互", "自研 CPU · 跑分与经典游戏"
};
static const char *const presets[] = {"原始", "自动亮度", "降噪", "自动亮度 + 降噪"};
static unsigned scene, selected, current;
static lv_obj_t *summary, *tag;
static unsigned tag_page;
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
    static const char *const map[] = {"原始","自动亮度","\n","降噪","亮度 + 降噪",""};
    lv_obj_t *control = ui_segment(parent,map,ui_data_preprocess().preset);
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
    if (!tag || tag_page != ui_page) return;
    ui_preprocess_t d = ui_data_preprocess();
    unsigned gain = d.preset == 1 || d.preset == 3 ? d.gain_q8 : 256;
    char text[160];
    lv_snprintf(text,sizeof text,"前处理：%s ×%u.%u · 亮度 %u",presets[d.preset],
        gain/256,(gain%256)*10/256,d.luma);
    ui_text(tag,text);
}
void ui_live_command(unsigned action, unsigned arg)
{
    if (action == 3) { ui_data_preprocess_set(arg); return; }
    if (action == 4) { scene = LIVE_DEMO_DIRECTORY; ui_open(LIVE_DEMO_PAGE); return; }
    if (action == 0) selected = arg-1;
    else selected = current ? current-1 : 0;
    if (action == 1) selected = current == 0 ? 0 : (selected+1)%10;
    if (action == 2) selected = current == 0 ? 9 : (selected+9)%10;
    current = scene = selected+1;
    ui_tab = ui_mode = 0;
    ui_detection_settings = false;
    if (selected == 7) ui_motion_entry = MOTION_SLING;
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
    lv_snprintf(text,sizeof text,"识别前处理：%s    画面亮度：%u",presets[d.preset],d.luma);
    ui_text(summary,text);
}
void ui_live_directory(lv_obj_t *parent)
{
    lv_obj_set_flex_flow(parent,LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_all(parent,20,0);
    lv_obj_set_style_pad_gap(parent,10,0);
    summary = ui_text_label(parent,"",&sim_font_20,TEXT);
    lv_obj_t *rows = ui_stack(parent,LV_FLEX_FLOW_ROW,20);
    lv_obj_set_flex_grow(rows,1);
    lv_obj_set_width(rows,LV_PCT(100));
    lv_obj_t *focus = NULL;
    for (unsigned chapter = 1; chapter <= 5; ++chapter) {
        lv_obj_t *column = ui_panel(rows,232);
        lv_obj_set_height(column,LV_PCT(100));
        char title[120];
        const char *name = chapter==1 ? "自研 NPU ·\n多模型部署" :
            chapter==5 ? "自研 CPU ·\n跑分与经典游戏" : chapters[chapter];
        lv_snprintf(title,sizeof title,"第 %u 章\n%s",chapter,name);
        lv_obj_t *heading = ui_text_label(column,title,&sim_font_20,ACCENT);
        lv_obj_set_size(heading,LV_PCT(100),80);
        for (unsigned i = 0; i < 10; ++i) {
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
            lv_obj_set_height(button,64);
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
    lv_snprintf(text,sizeof text,"现场演示 · 第 %u 章 %s · %s %u/10",
        scenes[i].chapter,chapters[scenes[i].chapter],scenes[i].name,scene);
    lv_obj_t *banner = ui_box(parent,0,0,1280,32,PANEL);
    lv_obj_set_clickable(banner,false);
    ui_label(banner,text,16,5,&sim_font_16,ACCENT);
}
bool ui_live_back(void)
{
    if (!scene) return false;
    if (scene == LIVE_DEMO_DIRECTORY) { scene = current = 0; ui_open(0); }
    else { selected = scene%10; scene = LIVE_DEMO_DIRECTORY; ui_open(LIVE_DEMO_PAGE); }
    return true;
}
