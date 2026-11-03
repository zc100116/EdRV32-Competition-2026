/* shell.c — showcase design §4.2; page lifetime, linear focus and four keys.
 * One group per active page; 2 Hz counters and 1 Hz monitoring curves.
 */
#include "theme.h"
unsigned ui_page;
unsigned ui_tab;
unsigned ui_mode;
bool ui_game_open;
static unsigned home_focus;
static bool game_back_armed;
static lv_group_t *group;
static lv_obj_t *content;
static lv_obj_t *status;
static lv_obj_t *hint;
static unsigned item_count;
static void activate(unsigned action);
static void clicked(lv_event_t *e)
{
    lv_obj_t *o = lv_event_get_target_obj(e);
    lv_group_focus_obj(o);
    activate((unsigned)(uintptr_t)lv_obj_get_user_data(o));
}
void ui_button(lv_obj_t *p, const char *s, int x, int y, int w, unsigned action)
{
    lv_obj_t *o = ui_box(p, x, y, w, 40, PANEL);
    ui_label(o, s, 14, 9, &sim_font_16, TEXT);
    lv_obj_set_clickable(o, true);
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
        case 1: ui_vision_update(false); break;
        case 2: ui_vision_update(true); break;
        case 4: ui_graphics_update(); break;
        case 6: ui_monitor_update(); break;
        case 7: ui_chip_update(); break;
        case 8: ui_debug_update(); break;
        default: break;
    }
}
void ui_open(unsigned page)
{
    ui_page = page;
    item_count = 0;
    if(group) lv_group_delete(group);
    group = lv_group_create();
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(BG), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);
    lv_obj_t *top = ui_box(screen, 0, 0, 1280, 48, PANEL);
    lv_obj_set_style_radius(top, 0, 0);
    ui_label(top, "EdRV32", 40, 9, &sim_font_20, ACCENT);
    const char *names[] = {"首页", "视觉识别", "图片识别", "图像处理", "图形引擎",
        "游戏", "系统监控", "芯片信息", "调试助手"};
    ui_label(top, names[page], 150, 12, &sim_font_16, TEXT);
    status = ui_label(top, "", 550, 14, &sim_font_14, MUTED);
    lv_obj_t *bottom = ui_box(screen, 0, 680, 1280, 40, PANEL);
    lv_obj_set_style_radius(bottom, 0, 0);
    hint = ui_label(bottom, "← → 选择    Enter 确认    Esc 返回首页", 40, 10,
                    &sim_font_14, MUTED);
    content = ui_box(screen, 0, 48, 1280, 632, BG);
    lv_obj_set_style_border_width(content, 0, 0);
    lv_obj_set_style_radius(content, 0, 0);
    void (*pages[])(lv_obj_t *) = {ui_page_home, ui_page_vision, ui_page_image,
        ui_page_process, ui_page_graphics, ui_page_games, ui_page_monitor,
        ui_page_chip, ui_page_debug};
    pages[page](content);
    if(page == 0) lv_group_focus_obj(lv_group_get_obj_by_index(group, home_focus));
    if(page == 3) lv_group_focus_obj(lv_group_get_obj_by_index(group, ui_mode));
    if(page == 4 || page == 8)
        lv_group_focus_obj(lv_group_get_obj_by_index(group, ui_tab));
    ui_refresh();
}
static void activate(unsigned action)
{
    if(ui_page == 0) {
        home_focus = action - 1;
        if(action == 3 && (ui_data_hardware() & (UI_PIX | UI_GEO)) != (UI_PIX | UI_GEO))
            return;
        ui_tab = 0;
        ui_mode = 0;
        ui_open(action);
    } else if(ui_page == 1) {
        if(action == 0) ui_data_pause();
        else ui_data_boxes();
        ui_refresh();
    } else if(ui_page == 2) {
        if(action == 0) { ui_data_batch_stop(); ui_refresh(); }
        else ui_open(1);
    } else if(ui_page == 3) { ui_mode = action; ui_open(3); }
    else if(ui_page == 4) {
        if(action < 3) { ui_tab = action; ui_open(4); }
        else { ui_data_benchmark_start(); ui_refresh(); }
    } else if(ui_page == 5) { ui_game_open = true; ui_mode = action; ui_open(5); }
    else if(ui_page == 7) { ui_data_coremark_start(); ui_refresh(); }
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
    if(key == LV_KEY_ESC) {
        if(ui_game_open) {
            if(game_back_armed) {
                ui_game_open = false;
                game_back_armed = false;
                ui_open(5);
            } else {
                game_back_armed = true;
                ui_hint("再按一次返回键退出游戏");
            }
        }
        else if((ui_page == 4 || ui_page == 8) && ui_tab) {
            ui_tab = 0;
            ui_open(ui_page);
        }
        else if(ui_page) ui_open(0);
    } else if(item_count) {
        game_back_armed = false;
        if(key == LV_KEY_LEFT) lv_group_focus_prev(group);
        if(key == LV_KEY_RIGHT) lv_group_focus_next(group);
        if(key == LV_KEY_ENTER) {
            lv_obj_t *o = lv_group_get_focused(group);
            activate((unsigned)(uintptr_t)lv_obj_get_user_data(o));
        }
    }
}
static void timer(lv_timer_t *t) { (void)t; ui_refresh(); }
void ui_start(void)
{
    theme_init();
    ui_open(0);
    lv_timer_create(timer, 500, NULL);
}
