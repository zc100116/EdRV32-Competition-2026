/* shell.c — showcase design §4.2; page lifetime, linear focus and four keys.
 * One group per active page; 2 Hz counters and 1 Hz monitoring curves.
 */
#include "theme.h"
#include "detection.h"
#include "renderer.h"
unsigned ui_page;
unsigned ui_tab;
unsigned ui_mode;
static bool game_active;
bool ui_game_active(void) { return game_active; }
bool ui_detection_settings;
static unsigned home_focus;
static unsigned game_focus;
static unsigned game_count;

static lv_group_t *group;
static lv_obj_t *content, *top, *bottom, *restore_surface, *hidden_focus;
static bool interface_hidden;
bool ui_interface_hidden(void) { return interface_hidden; }
void ui_hide_interface(void)
{
    hidden_focus=lv_group_get_focused(group);
    interface_hidden=true;
    lv_obj_set_hidden(top,true); lv_obj_set_hidden(bottom,true); lv_obj_set_hidden(content,true);
    lv_obj_set_hidden(restore_surface,false);
    lv_obj_update_layout(restore_surface);
    ui_monitor_suppress(true);
}
bool ui_restore_interface(void)
{
    if(!interface_hidden) return false;
    interface_hidden=false;
    lv_obj_set_hidden(top,false); lv_obj_set_hidden(bottom,false); lv_obj_set_hidden(content,false);
    lv_obj_set_hidden(restore_surface,true);
    ui_monitor_suppress(false);
    lv_group_focus_obj(hidden_focus);
    return true;
}
static void restore_pressed(lv_event_t *e)
{
    (void)e;
    ui_restore_interface();
    lv_indev_wait_release(lv_indev_active());
}
static lv_obj_t *status;
static lv_obj_t *hint;
static lv_obj_t *session_box, *session_text, *retry;
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
    activate((unsigned)(uintptr_t)lv_obj_get_user_data(o));
}
enum { KEY_EDIT=0x100, KEY_BACK=0x101 };
static bool editable(lv_obj_t *o)
{
    return lv_obj_check_type(o,&lv_slider_class) || lv_obj_check_type(o,&lv_dropdown_class);
}
static lv_key_t remap(lv_indev_t *input,lv_key_t key)
{
    if(interface_hidden && lv_indev_get_state(input)==LV_INDEV_STATE_PRESSED) {
        ui_restore_interface(); lv_indev_wait_release(input); return 0;
    }
    lv_obj_t *o=lv_group_get_focused(group);
    if(key==LV_KEY_ESC) return (lv_key_t)KEY_BACK;
    if(key==LV_KEY_ENTER && o && editable(o)) return (lv_key_t)KEY_EDIT;
    bool editing=lv_group_get_editing(group);
    if(key==LV_KEY_NEXT || key==LV_KEY_RIGHT) return editing ? LV_KEY_RIGHT : LV_KEY_NEXT;
    if(key==LV_KEY_PREV || key==LV_KEY_LEFT) return editing ? LV_KEY_LEFT : LV_KEY_PREV;
    return key;
}
static void key_event(lv_event_t *e)
{
    uint32_t key=lv_event_get_key(e);
    lv_obj_t *o=lv_event_get_target_obj(e);
    if(key==KEY_EDIT) {
        bool editing=lv_group_get_editing(group);
        if(lv_obj_check_type(o,&lv_dropdown_class)) {
            if(editing) {
                lv_dropdown_close(o);
                lv_obj_send_event(o,LV_EVENT_VALUE_CHANGED,NULL);
            } else lv_dropdown_open(o);
        }
        lv_group_set_editing(group,!editing);
    } else if(key==KEY_BACK) ui_back();
    else if(key==LV_KEY_ESC) ui_back();
}
static void focused(lv_event_t *e)
{
    lv_obj_scroll_to_view_recursive(lv_event_get_target_obj(e), LV_ANIM_OFF);
}
static void pointer_pressed(lv_event_t *e)
{
    lv_indev_t *input=lv_indev_active();
    if(input && lv_indev_get_type(input)==LV_INDEV_TYPE_POINTER) {
        lv_obj_remove_state(lv_event_get_target_obj(e),LV_STATE_FOCUS_KEY);
        lv_group_set_editing(group,false);
    }
}
void ui_control(lv_obj_t *o)
{
    lv_obj_set_scroll_on_focus(o,true);
    lv_obj_add_event_cb(o,focused,LV_EVENT_FOCUSED,NULL);
    lv_obj_add_event_cb(o,key_event,LV_EVENT_KEY,NULL);
    lv_obj_add_event_cb(o,pointer_pressed,LV_EVENT_PRESSED,NULL);
    lv_group_add_obj(group,o);
}
void ui_button(lv_obj_t *p, const char *s, int x, int y, int w, unsigned action)
{
    lv_obj_t *o=lv_button_create(p);
    ui_control_style(o);
    lv_obj_set_pos(o,x,y); lv_obj_set_size(o,w,40);
    ui_label(o,s,14,9,&sim_font_16,TEXT);
    lv_obj_add_event_cb(o,clicked,LV_EVENT_CLICKED,NULL);
    lv_obj_set_user_data(o,(void *)(uintptr_t)action);
    ui_control(o);
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
    ui_session_t session=ui_data_session();
    if(game_active && session.app==UI_APP_GAME && session.state==UI_STATE_IDLE) {
        game_active=false; ui_open(5); return;
    }
    bool show=session.app!=UI_APP_NONE && (session.state==UI_STATE_STARTING ||
        session.state==UI_STATE_STOPPING || session.state==UI_STATE_FAILED);
    lv_obj_set_hidden(session_box,!show);
    lv_obj_set_hidden(retry,session.state!=UI_STATE_FAILED);
    if(show) ui_text(session_text,session.state==UI_STATE_FAILED ? session.error :
        session.state==UI_STATE_STARTING ? "正在启动" : "正在停止");
    switch(ui_page) {
        case 1: if(!ui_detection_settings) ui_vision_update(false); break;
        case 2: if(!ui_detection_settings) ui_vision_update(true); break;
        case 9: ui_pose_update(); break;
        case 3: ui_process_update(); break;
        case 4: ui_graphics_update(); break;
        case 5: {
            unsigned count; ui_data_games(&count);
            if(!game_active && count!=game_count) ui_open(5);
            break;
        }

        case 7: ui_chip_update(); break;
        case 8: ui_debug_update(); break;
        default: break;
    }
}
void ui_open(unsigned page)
{
    if(page==6) { ui_monitor_toggle(); return; }
    interface_hidden=false; ui_monitor_suppress(false);
    unsigned old_page=ui_page;
    if(old_page!=page) {
        ui_mode=0;
        static const ui_app_t apps[]={UI_APP_NONE,UI_APP_CAMERA,UI_APP_IMAGE,
            UI_APP_PROCESS,UI_APP_GRAPHICS,UI_APP_NONE,UI_APP_NONE,UI_APP_NONE,UI_APP_NONE,
            UI_APP_POSE};
        if(apps[old_page]!=UI_APP_NONE || game_active ||
           ui_data_session().app==UI_APP_COREMARK) ui_data_app_open(UI_APP_NONE,0);
        game_active=false;
        if(apps[page]!=UI_APP_NONE) ui_data_app_open(apps[page],0);
    }
    ui_page = page;
    if(page!=1 && page!=2) ui_detection_settings=false;
    if(group) lv_group_delete(group);
    group = lv_group_create();
    lv_group_set_default(group);
    for(lv_indev_t *input=lv_indev_get_next(NULL);input;input=lv_indev_get_next(input))
        if(lv_indev_get_type(input)!=LV_INDEV_TYPE_POINTER) {
            lv_indev_set_group(input,group);
            if(lv_indev_get_type(input)==LV_INDEV_TYPE_KEYPAD)
                lv_indev_set_key_remap_cb(input,remap);
        }
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(BG), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);
    top = ui_box(screen, 0, 0, 1280, 48, PANEL);
    lv_obj_set_style_radius(top, 0, 0);
    ui_label(top, "EdRV32", 140, 9, &sim_font_20, ACCENT);
    const char *names[] = {"首页", "视觉识别", "图片识别", "图像处理", "图形引擎",
        "游戏", "系统监控", "芯片信息", "调试助手", "人体姿态"};
    ui_label(top, names[page], 260, 12, &sim_font_16, TEXT);
    status = ui_label(top, "", 420, 14, &sim_font_14, MUTED);
    ui_button(top,"‹ 返回",12,6,108,1000);
    lv_obj_set_height(lv_obj_get_child(top,-1),36);
    ui_button(top,"性能浮窗",1140,6,124,1001);
    lv_obj_set_height(lv_obj_get_child(top,-1),36);
    bottom = ui_box(screen, 0, 680, 1280, 40, PANEL);
    lv_obj_set_style_radius(bottom, 0, 0);
    hint = ui_label(bottom, "← → 选择    Enter 确认    Esc 返回上一级", 40, 10,
                    &sim_font_14, MUTED);
    content = ui_box(screen, 0, 48, 1280, 632, BG);
    lv_obj_set_style_border_width(content, 0, 0);
    lv_obj_set_style_radius(content, 0, 0);
    void (*pages[])(lv_obj_t *) = {ui_page_home, ui_page_vision, ui_page_image,
        ui_page_process, ui_page_graphics, ui_page_games, NULL,
        ui_page_chip, ui_page_debug, ui_page_pose};
    if(page==5) ui_data_games(&game_count);
    if(ui_detection_settings) ui_page_detection_settings(content);
    else pages[page](content);
    session_box=ui_box(content,340,200,600,164,PANEL);
    session_text=ui_label(session_box,"",24,22,&sim_font_20,TEXT);
    lv_obj_set_width(session_text,552);
    ui_button(session_box,"重试",24,102,160,1002);
    retry=lv_obj_get_child(session_box,-1);
    lv_obj_set_hidden(session_box,true);
    if(page!=5 || !game_active)
        lv_group_focus_obj(lv_group_get_obj_by_index(group,2));
    if(page == 0) lv_group_focus_obj(lv_group_get_obj_by_index(group, home_focus+2));
    if(page == 5 && !game_active)
        lv_group_focus_obj(lv_group_get_obj_by_index(group, game_focus+2));
    if(page == 3) lv_group_focus_obj(lv_group_get_obj_by_index(group, ui_mode+2));
    if(page == 4 || page == 8)
        lv_group_focus_obj(lv_group_get_obj_by_index(group, ui_tab+2));
    if((page>=1 && page<=3) || page==9) {
        ui_button(bottom,"隐藏界面",1104,0,160,1005);
        lv_obj_set_height(lv_obj_get_child(bottom,-1),36);
        restore_surface=ui_box(screen,0,0,1280,720,0);
        lv_obj_set_style_bg_opa(restore_surface,LV_OPA_TRANSP,0);
        lv_obj_set_style_border_width(restore_surface,0,0);
        lv_obj_set_clickable(restore_surface,true);
        lv_obj_add_event_cb(restore_surface,restore_pressed,LV_EVENT_PRESSED,NULL);
        lv_obj_set_hidden(restore_surface,true);
    }
    ui_monitor_controls();
    ui_refresh();
}
static void activate(unsigned action)
{
    if(action==1005) { ui_hide_interface(); return; }
    if(action==1000) { ui_back(); return; }
    if(action==1001) { ui_monitor_toggle(); return; }
    if(action==1003) { ui_monitor_corner(); return; }
    if(action==1004) { ui_data_benchmark_stop(); return; }
    if(action==1002) { ui_data_app_retry(); ui_refresh(); return; }
    if(ui_page == 0) {
        home_focus = action - 1;
        const unsigned required[]={0,UI_VIN|UI_NPU,UI_VIN|UI_NPU|UI_ETH,
            UI_VIN|UI_PIX|UI_GEO,UI_RND|UI_DISP,UI_RND|UI_DISP,0,0,0,UI_VIN|UI_NPU};
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
    } else if(ui_page == 1 || ui_page == 9) {
        if(action == 0) ui_data_app_pause(ui_data_session().state!=UI_STATE_PAUSED);
        else ui_data_boxes();
        ui_refresh();
    } else if(ui_page == 2) {
        if(action==0 || action==1) ui_data_image_step(action==0 ? -1 : 1);
        ui_refresh();
    } else if(ui_page == 3) { ui_process_action(action); }
    else if(ui_page == 4) {
        ui_graphics_action(action);
    } else if(ui_page == 5) {
        game_focus = action;
        game_active = true;
        ui_mode = action;
        ui_data_app_open(UI_APP_GAME,action);
        ui_open(5);
    }
    else if(ui_page == 7) {
        if(action==1) { ui_tab=1; ui_open(7); }
        else { ui_data_app_open(UI_APP_COREMARK,0); ui_refresh(); }
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
    if(ui_restore_interface()) return;
    key=remap(NULL,key);
    if(key==KEY_BACK) { ui_back(); return; }
    if(key==LV_KEY_NEXT) lv_group_focus_next(group);
    else if(key==LV_KEY_PREV) lv_group_focus_prev(group);
    else {
        lv_obj_t *o=lv_group_get_focused(group);
        if(lv_obj_has_state(o,LV_STATE_DISABLED)) return;
        lv_obj_add_state(o,LV_STATE_FOCUS_KEY);
        if(key==LV_KEY_ENTER) {
            if(lv_obj_is_checkable(o)) {
                if(lv_obj_has_state(o,LV_STATE_CHECKED)) lv_obj_remove_state(o,LV_STATE_CHECKED);
                else lv_obj_add_state(o,LV_STATE_CHECKED);
                lv_obj_send_event(o,LV_EVENT_VALUE_CHANGED,NULL);
            }
            lv_obj_send_event(o,LV_EVENT_CLICKED,NULL);
        } else lv_group_send_data(group,key);
    }
    lv_obj_add_state(lv_group_get_focused(group),LV_STATE_FOCUS_KEY);
}
void ui_back(void)
{
    lv_obj_t *o=lv_group_get_focused(group);
    bool dropdown_open=o && lv_obj_check_type(o,&lv_dropdown_class) && lv_dropdown_is_open(o);
    if(lv_group_get_editing(group) || dropdown_open) {
        if(lv_obj_check_type(o,&lv_dropdown_class)) {
            lv_dropdown_close(o); lv_obj_send_event(o,LV_EVENT_VALUE_CHANGED,NULL);
        }
        lv_group_set_editing(group,false); return;
    }
    if(ui_detection_settings) { ui_detection_settings=false; ui_open(ui_page); }
    else if(game_active) { game_active=false; ui_data_app_open(UI_APP_NONE,0); ui_open(5); }
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

void ui_show_app(ui_app_t app,unsigned arg)
{
    static const unsigned pages[]={0,1,2,3,4,5,7,9};
    ui_detection_settings=false; ui_tab=0; ui_mode=0;
    game_active=app==UI_APP_GAME;
    if(game_active) { game_focus=arg; ui_mode=arg; }
    /* The backend already accepted the PC command; page selection does not request it again. */
    ui_page=pages[app];
    ui_open(pages[app]);
}
