/* shell.c — showcase design §4.2; page lifetime, linear focus and four keys.
 * One group per active page; 2 Hz counters and 1 Hz monitoring curves.
 */
#include "theme.h"
#include "detection.h"
#include "renderer.h"
unsigned ui_page;
unsigned ui_tab;
unsigned ui_mode;
bool ui_game_open;
bool ui_detection_settings;
static unsigned home_focus;
static unsigned game_focus;
static unsigned game_count;

static lv_group_t *group;
static lv_obj_t *content;
static lv_obj_t *status;
static lv_obj_t *hint;
static unsigned item_count;
static lv_timer_t *refresh_timer;
void ui_suspend(bool paused)
{
    if(paused) lv_timer_pause(refresh_timer);
    else lv_timer_resume(refresh_timer);
}
static void activate(unsigned action);
static void clicked(lv_event_t *e)
{
    lv_obj_t *o = lv_event_get_target_obj(e);
    lv_group_focus_obj(o);
    activate((unsigned)(uintptr_t)lv_obj_get_user_data(o));
}
static void key_event(lv_event_t *e)
{
    uint32_t key=lv_event_get_key(e);
    if(key==LV_KEY_ESC || key==LV_KEY_LEFT || key==LV_KEY_RIGHT) ui_key(key);
}
static void focused(lv_event_t *e)
{
    lv_obj_scroll_to_view_recursive(lv_event_get_target_obj(e), LV_ANIM_OFF);
}
void ui_button(lv_obj_t *p, const char *s, int x, int y, int w, unsigned action)
{
    lv_obj_t *o = ui_box(p, x, y, w, 40, PANEL);
    ui_label(o, s, 14, 9, &sim_font_16, TEXT);
    lv_obj_set_clickable(o, true);
    lv_obj_set_scroll_on_focus(o, false);
    lv_obj_add_event_cb(o, focused, LV_EVENT_FOCUSED, NULL);
    lv_obj_add_event_cb(o, key_event, LV_EVENT_KEY, NULL);
    lv_obj_add_event_cb(o, clicked, LV_EVENT_CLICKED, NULL);
    lv_obj_set_user_data(o, (void *)(uintptr_t)action);
    ++item_count;
    lv_group_add_obj(group, o);
}
void ui_hint(const char *s) { ui_text(hint, s); }
void ui_refresh(void)
{
    ui_system_t d = ui_data_system();
    char s[160];
    lv_snprintf(s, sizeof(s), "运行 %02u:%02u:%02u     CPU %u%%     网口 %s     GUI %u FPS",
        d.seconds / 3600, d.seconds / 60 % 60, d.seconds % 60, d.cpu,
        d.link ? "已连接" : "未连接", d.fps);
    ui_text(status, s);
    switch(ui_page) {
        case 1: if(!ui_detection_settings) ui_vision_update(false); break;
        case 2: if(!ui_detection_settings) ui_vision_update(true); break;
        case 3: ui_process_update(); break;
        case 4: ui_graphics_update(); break;
        case 5: {
            unsigned count; ui_data_games(&count);
            if(!ui_game_open && count!=game_count) ui_open(5);
            break;
        }

        case 7: ui_chip_update(); break;
        case 8: ui_debug_update(); break;
        default: break;
    }
}
static void back_clicked(lv_event_t *e) { (void)e; ui_back(); }
static void monitor_clicked(lv_event_t *e) { (void)e; ui_monitor_toggle(); }
void ui_open(unsigned page)
{
    if(page==6) { ui_monitor_toggle(); return; }
    ui_page = page;
    if(page!=1 && page!=2) ui_detection_settings=false;
    item_count = 0;
    if(group) lv_group_delete(group);
    group = lv_group_create();
    lv_group_set_default(group);
    for(lv_indev_t *input=lv_indev_get_next(NULL);input;input=lv_indev_get_next(input))
        if(lv_indev_get_type(input)!=LV_INDEV_TYPE_POINTER) lv_indev_set_group(input,group);
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(BG), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);
    lv_obj_t *top = ui_box(screen, 0, 0, 1280, 48, PANEL);
    lv_obj_set_style_radius(top, 0, 0);
    ui_label(top, "EdRV32", 140, 9, &sim_font_20, ACCENT);
    const char *names[] = {"首页", "视觉识别", "图片识别", "图像处理", "图形引擎",
        "游戏", "系统监控", "芯片信息", "调试助手"};
    ui_label(top, names[page], 260, 12, &sim_font_16, TEXT);
    status = ui_label(top, "", 420, 14, &sim_font_14, MUTED);
    lv_obj_t *toggle=ui_box(top,1140,6,124,36,SELECTED);
    ui_label(toggle,"性能浮窗",14,8,&sim_font_14,ACCENT);
    lv_obj_set_clickable(toggle,true);
    lv_obj_add_event_cb(toggle,monitor_clicked,LV_EVENT_CLICKED,NULL);
    lv_obj_t *bottom = ui_box(screen, 0, 680, 1280, 40, PANEL);
    lv_obj_set_style_radius(bottom, 0, 0);
    hint = ui_label(bottom, "← → 选择    Enter 确认    Esc 返回上一级", 40, 10,
                    &sim_font_14, MUTED);
    content = ui_box(screen, 0, 48, 1280, 632, BG);
    lv_obj_set_style_border_width(content, 0, 0);
    lv_obj_set_style_radius(content, 0, 0);
    void (*pages[])(lv_obj_t *) = {ui_page_home, ui_page_vision, ui_page_image,
        ui_page_process, ui_page_graphics, ui_page_games, NULL,
        ui_page_chip, ui_page_debug};
    if(page==5) ui_data_games(&game_count);
    if(ui_detection_settings) ui_page_detection_settings(content);
    else pages[page](content);
    if(page) {
        lv_obj_t *back=ui_box(top,12,6,108,36,PANEL);
        ui_label(back,"‹ 返回",14,8,&sim_font_16,ACCENT);
        lv_obj_set_clickable(back,true);
        lv_obj_add_event_cb(back,back_clicked,LV_EVENT_CLICKED,NULL);
    }
    if(!item_count) {
        lv_group_add_obj(group,content);
        lv_obj_add_event_cb(content,key_event,LV_EVENT_KEY,NULL);
    }
    if(page == 0) lv_group_focus_obj(lv_group_get_obj_by_index(group, home_focus));
    if(page == 5 && !ui_game_open)
        lv_group_focus_obj(lv_group_get_obj_by_index(group, game_focus));
    if(page == 3) lv_group_focus_obj(lv_group_get_obj_by_index(group, ui_mode));
    if(page == 4 || page == 8)
        lv_group_focus_obj(lv_group_get_obj_by_index(group, ui_tab));
    ui_refresh();
}
static void activate(unsigned action)
{
    if(ui_page == 0) {
        home_focus = action - 1;
        const unsigned required[]={0,UI_VIN|UI_NPU,UI_VIN|UI_NPU|UI_ETH,
            UI_VIN|UI_PIX|UI_GEO,UI_RND|UI_DISP,UI_RND|UI_DISP,0,0,0};
        if((ui_data_hardware()&required[action])!=required[action]) return;
        ui_tab = 0;
        ui_mode = 0;
        game_focus = 0;
        if(action==6) ui_monitor_toggle();
        else ui_open(action);
    } else if((ui_page==1 || ui_page==2) && ui_detection_settings) {
        ui_detection_settings_action(action);
    } else if((ui_page==1 || ui_page==2) && action==2) {
        ui_detection_settings=true; ui_open(ui_page);
    } else if(ui_page == 1) {
        if(action == 0) ui_data_pause();
        else ui_data_boxes();
        ui_refresh();
    } else if(ui_page == 2) {
        if(action == 0) { ui_data_batch_stop(); ui_refresh(); }
        else ui_open(1);
    } else if(ui_page == 3) { ui_process_action(action); }
    else if(ui_page == 4) {
        ui_graphics_action(action);
    } else if(ui_page == 5) {
        game_focus = action;
        ui_game_open = true;
        ui_mode = action;
        ui_open(5);
    }
    else if(ui_page == 7) {
        if(action==1) { ui_tab=1; ui_open(7); }
        else { ui_data_coremark_start(); ui_refresh(); }
    }
    else if(ui_page == 8) {
        if(action < 2) { ui_tab = action; ui_open(8); }
        else {
            if(action == 2) ui_data_debug_format();
            if(action == 3) ui_data_debug_baud();
            if(action == 4) ui_data_debug_send();
            if(action == 5) ui_data_debug_clear();
            if(action == 6) ui_data_debug_echo();
            ui_refresh();
        }
    }
}
void ui_key(uint32_t key)
{
    if(key == LV_KEY_ESC) { ui_back();
    } else if(item_count) {
        if(key == LV_KEY_LEFT) lv_group_focus_prev(group);
        if(key == LV_KEY_RIGHT) lv_group_focus_next(group);
        if(key == LV_KEY_ENTER) {
            lv_obj_t *o = lv_group_get_focused(group);
            activate((unsigned)(uintptr_t)lv_obj_get_user_data(o));
        }
    }
}
void ui_back(void)
{
    if(ui_detection_settings) { ui_detection_settings=false; ui_open(ui_page); }
    else if(ui_game_open) { ui_game_open=false; ui_open(5); }
    else if(ui_page==4 && ui_data_benchmark_running()) {
        ui_data_benchmark_stop();
    } else if((ui_page==4 || ui_page==7 || ui_page==8) && ui_tab) {
        if(ui_page==4 && ui_mode) ui_mode=0;
        else ui_tab=0;
        ui_open(ui_page);
    } else if(ui_page) ui_open(0);
}
static void timer(lv_timer_t *t) { (void)t; ui_refresh(); }
void ui_start(void)
{
    theme_init();
    ui_monitor_init();
    ui_open(0);
    refresh_timer=lv_timer_create(timer, 500, NULL);
}
