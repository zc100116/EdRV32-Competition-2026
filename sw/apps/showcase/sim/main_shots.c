/* main_shots.c — design P1a §5: headless RGB565 captures; scripted LVGL clock. */
#include "theme.h"
#include "sim_data.h"
#include "renderer.h"
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

static uint16_t framebuffer[1280 * 720];
static uint32_t drawbuffer[1280 * 720];

static lv_indev_data_t test_input;
static void read_test_input(lv_indev_t *indev,lv_indev_data_t *data)
{
    (void)indev; *data=test_input; test_input.enc_diff=0;
}
static void key_tap(lv_indev_t *indev,uint32_t key)
{
    test_input.key=key; test_input.state=LV_INDEV_STATE_PRESSED; lv_indev_read(indev);
    test_input.state=LV_INDEV_STATE_RELEASED; lv_indev_read(indev);
}
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const lv_image_dsc_t *l0 = sim_l0_image();
    const uint32_t *source = (const uint32_t *)pixels;
    for(int y = area->y1; y <= area->y2; ++y)
        for(int x = area->x1; x <= area->x2; ++x)
        {
            uint32_t pixel = sim_composite(l0, *source++, (unsigned)x, (unsigned)y);
            framebuffer[y * 1280 + x] = (uint16_t)(((pixel >> 8)&0xf800) |
                ((pixel >> 5)&0x07e0) | ((pixel >> 3)&31));
        }
    lv_display_flush_ready(display);
}

static void check_labels(lv_obj_t *parent)
{
    for(unsigned i = 0; i < lv_obj_get_child_count(parent); ++i) {
        lv_obj_t *o = lv_obj_get_child(parent, (int)i);
        if(lv_obj_is_hidden(o)) continue;
        if(lv_obj_check_type(o, &lv_label_class) && lv_label_get_text(o)[0]) {
            const unsigned char *text = (const unsigned char *)lv_label_get_text(o);
            const lv_font_t *font = lv_obj_get_style_text_font(o, 0);
            while(*text) {
                unsigned code = *text++;
                if(code >= 0xc0) {
                    unsigned n = code >= 0xf0 ? 3 : code >= 0xe0 ? 2 : 1;
                    code &= (1u << (6 - n)) - 1;
                    while(n--) code = (code << 6) | (*text++ & 0x3f);
                }
                if(code == '\n') continue;
                lv_font_glyph_dsc_t glyph;
                if(!lv_font_get_glyph_dsc(font, &glyph, code, 0) || glyph.is_placeholder) {
                    fprintf(stderr, "Missing glyph U+%04X in %s\n", code,
                        lv_label_get_text(o));
                    exit(EXIT_FAILURE);
                }
            }
            if(!lv_obj_is_scrollable(parent) && (lv_obj_get_x(o) < 0 || lv_obj_get_y(o) < 0 ||
                lv_obj_get_x(o) + lv_obj_get_width(o) > lv_obj_get_width(parent) ||
                lv_obj_get_y(o) + lv_obj_get_height(o) > lv_obj_get_height(parent))) {
                fprintf(stderr, "Label outside parent: %s (%d,%d %dx%d in %dx%d)\n",
                    lv_label_get_text(o), (int)lv_obj_get_x(o), (int)lv_obj_get_y(o),
                    (int)lv_obj_get_width(o), (int)lv_obj_get_height(o),
                    (int)lv_obj_get_width(parent), (int)lv_obj_get_height(parent));
                exit(EXIT_FAILURE);
            }
        }
        check_labels(o);
    }
}

static void capture(const char *name)
{
    lv_obj_update_layout(lv_screen_active());
    lv_obj_invalidate(lv_screen_active());
    lv_refr_now(NULL);
    check_labels(lv_screen_active());
    check_labels(lv_layer_sys());
    char path[256];
    snprintf(path, sizeof(path), "shots/%s.rgb565", name);
    FILE *file = fopen(path, "wb");
    if(!file) { perror(path); exit(EXIT_FAILURE); }
    if(fwrite(framebuffer, sizeof(framebuffer), 1, file) != 1) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    if(fclose(file)) { perror(path); exit(EXIT_FAILURE); }
}

static void measure_flush(lv_display_t *d,const lv_area_t *a,uint8_t *p)
{ (void)a; (void)p; lv_display_flush_ready(d); }
static uint64_t host_ns(void)
{
    struct timespec ts; timespec_get(&ts,TIME_UTC);
    return (uint64_t)ts.tv_sec*1000000000u+(uint64_t)ts.tv_nsec;
}
static void measure_overlay(void)
{
    lv_display_t *main=lv_display_get_default();
    lv_display_t *small=lv_display_create(320,240);
    static uint32_t pixels[320*240];
    lv_display_set_color_format(small,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(small,pixels,NULL,sizeof(pixels),LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(small,measure_flush);
    lv_display_set_default(small);
    ui_monitor_parent(lv_screen_active(),true);
    if(!ui_monitor_visible()) ui_monitor_toggle();
    uint64_t total=0,max=0;
    for(unsigned i=0;i<120;++i) {
        lv_tick_inc(500);
        uint64_t start=host_ns(); ui_monitor_update(); lv_refr_now(small);
        uint64_t elapsed=host_ns()-start; total+=elapsed; if(elapsed>max) max=elapsed;
    }
    printf("Overlay 320x240 ARGB software, 120 refreshes: average_us=%llu max_us=%llu\n",
        (unsigned long long)(total/120/1000),(unsigned long long)(max/1000));
    ui_monitor_toggle();
    lv_display_set_default(main);
    ui_monitor_parent(lv_layer_sys(),false);
    lv_display_delete(small);
}
static lv_indev_t *keypad;
static void tap(uint32_t key) { key_tap(keypad,key); }
static lv_obj_t *focus(void) { return lv_group_get_focused(lv_group_get_default()); }
static void settle(void) { lv_tick_inc(150); ui_refresh(); }
static void select_control(lv_obj_t *target)
{
    unsigned n=lv_group_get_obj_count(lv_group_get_default());
    for(unsigned i=0;i<n && focus()!=target;++i) tap(LV_KEY_NEXT);
    assert(focus()==target);
}
static lv_obj_t *control(unsigned index)
{ return lv_group_get_obj_by_index(lv_group_get_default(),index); }
static bool available(lv_obj_t *o)
{
    if(lv_obj_has_state(o,LV_STATE_DISABLED)) return false;
    for(lv_obj_t *p=o;p;p=lv_obj_get_parent(p)) if(lv_obj_is_hidden(p)) return false;
    return true;
}
/* Enumerate actual interactive descendants, not a page-specific expected count. */
static void check_registered(lv_obj_t *parent)
{
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *o=lv_obj_get_child(parent,(int)i);
        if(available(o) && (lv_obj_check_type(o,&lv_button_class) ||
           lv_obj_check_type(o,&lv_slider_class) || lv_obj_check_type(o,&lv_switch_class) ||
           lv_obj_check_type(o,&lv_dropdown_class) || lv_obj_check_type(o,&lv_checkbox_class)))
            assert(lv_obj_get_group(o)==lv_group_get_default());
        check_registered(o);
    }
}
static void traverse(void)
{
    lv_group_t *g=lv_group_get_default();
    unsigned n=lv_group_get_obj_count(g), count=0;
    check_registered(lv_screen_active()); check_registered(lv_layer_sys());
    for(unsigned i=0;i<n;++i) {
        lv_obj_t *target=control(i);
        if(!available(target)) continue;
        select_control(target); ++count;
        assert(lv_obj_has_state(target,LV_STATE_FOCUS_KEY));
        lv_obj_update_layout(lv_screen_active());
        lv_area_t a; lv_obj_get_coords(target,&a);
        assert(a.y1>=0 && a.y2<720);
        tap(LV_KEY_NEXT); tap(LV_KEY_PREV); assert(focus()==target);
    }
    assert(count>=2);
}
static void pointer(lv_indev_t *mouse,int x,int y,bool pressed)
{
    test_input.point=(lv_point_t){x,y};
    test_input.state=pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    lv_indev_read(mouse);
}
static void check_four_keys(void)
{
    for(unsigned page=0;page<=8;++page) {
        if(page==6) continue;
        ui_tab=0; ui_mode=0; ui_open(page); settle();
        if(page==2) sim_data_image_status(UI_IMAGE_DONE);
        if(page==3) {
            ui_process_config_t c=ui_data_process_config(); c.enabled=UI_PROC_ALL;
            ui_data_process_set(&c);
        }
        ui_refresh(); traverse();
    }
    ui_open(1); settle();
    select_control(control(2)); tap(LV_KEY_ENTER);
    assert(ui_data_session().state==UI_STATE_PAUSED);
    tap(LV_KEY_ENTER); assert(ui_data_session().state==UI_STATE_RUNNING);
    tap(LV_KEY_NEXT); bool boxes=ui_data_vision().boxes;
    tap(LV_KEY_ENTER); assert(ui_data_vision().boxes!=boxes);
    tap(LV_KEY_NEXT); tap(LV_KEY_ENTER); assert(ui_detection_settings);
    traverse();
    select_control(control(2));
    unsigned threshold=ui_data_detection_config().threshold;
    tap(LV_KEY_ENTER); assert(lv_group_get_editing(lv_group_get_default()));
    tap(LV_KEY_PREV); assert(ui_data_detection_config().threshold==threshold-5);
    tap(LV_KEY_ESC); assert(ui_detection_settings && !lv_group_get_editing(lv_group_get_default()));
    tap(LV_KEY_NEXT); tap(LV_KEY_NEXT); tap(LV_KEY_ENTER);
    assert(ui_data_detection_config().classes[0]==0);
    tap(LV_KEY_NEXT); tap(LV_KEY_ENTER); assert(ui_data_detection_config().classes[0]==1);
    capture("detection-settings");
    tap(LV_KEY_ESC); assert(!ui_detection_settings && ui_page==1);
    tap(LV_KEY_ESC); assert(ui_page==0);
    ui_data_detection_threshold(50); ui_data_detection_all(true);
    if(!ui_data_vision().boxes) ui_data_boxes();

    ui_open(3); settle();
    ui_process_config_t preview=ui_data_process_config();
    preview.enabled=UI_PROC_LEVEL | UI_PROC_GAMMA | UI_PROC_S1;
    ui_data_process_set(&preview); ui_refresh();
    select_control(control(5)); /* first enable switch after page toolbar */
    ui_process_config_t c=ui_data_process_config();
    if(!(c.enabled&UI_PROC_LEVEL)) tap(LV_KEY_ENTER);
    select_control(control(6));
    int value=ui_data_process_config().brightness;
    tap(LV_KEY_ENTER); assert(lv_group_get_editing(lv_group_get_default()));
    tap(LV_KEY_NEXT); assert(ui_data_process_config().brightness==value+1);
    capture("process-editing");
    tap(LV_KEY_ENTER); assert(!lv_group_get_editing(lv_group_get_default()));
    tap(LV_KEY_PREV); tap(LV_KEY_ENTER);
    assert(!(ui_data_process_config().enabled&UI_PROC_LEVEL));
    assert(ui_data_process_config().brightness==value+1);
    capture("process-stage-off");
    tap(LV_KEY_ENTER); assert(ui_data_process_config().brightness==value+1);
    /* S1 dropdown: enter edit, next selects, Esc commits one level. */
    lv_obj_t *dropdown=NULL;
    for(unsigned i=0;i<lv_group_get_obj_count(lv_group_get_default());++i)
        if(lv_obj_check_type(control(i),&lv_dropdown_class)) { dropdown=control(i); break; }
    select_control(dropdown); int stage=ui_data_process_config().stage1;
    tap(LV_KEY_ENTER); tap(LV_KEY_NEXT); tap(LV_KEY_ESC);
    assert(ui_page==3 && !lv_group_get_editing(lv_group_get_default()));
    assert(ui_data_process_config().stage1==stage+1);
    select_control(control(8)); tap(LV_KEY_ENTER);
    assert(ui_data_process_config().brightness==0);
    assert(ui_data_process_config().enabled==preview.enabled);
    assert(ui_data_process_config().stage1==stage+1);
    select_control(control(31)); capture("process-geo");
    select_control(control(4)); tap(LV_KEY_ENTER);
    assert(ui_data_process_config().enabled==0 && ui_data_process_config().brightness==0);
    select_control(control(2)); tap(LV_KEY_ENTER); traverse(); capture("process-collapsed");
    select_control(control(2)); tap(LV_KEY_ENTER); capture("process");

    ui_open(2); settle(); sim_data_image_status(UI_IMAGE_DONE); ui_refresh();
    select_control(control(3)); unsigned image=ui_data_vision().image_index;
    tap(LV_KEY_ENTER); assert(ui_data_vision().image_index==image+1);
    sim_data_image_status(UI_IMAGE_DONE); ui_refresh();
    select_control(control(2)); tap(LV_KEY_ENTER); assert(ui_data_vision().image_index==image);
    const char *image_names[]={"image-waiting","image-receiving","image-detecting",
        "image-done","image-failed"};
    for(unsigned i=0;i<5;++i) {
        sim_data_image_status((int)i); ui_refresh();
        bool busy=i==1 || i==2;
        assert(lv_obj_has_state(control(2),LV_STATE_DISABLED)==busy);
        assert(lv_obj_has_state(control(3),LV_STATE_DISABLED)==busy);
        if(busy) { ui_data_image_step(1); assert(ui_data_vision().image_index==image); }
        capture(image_names[i]);
    }
    sim_data_image_status(UI_IMAGE_DONE); ui_refresh(); select_control(control(2));
    sim_data_image_status(UI_IMAGE_RECEIVING); ui_refresh(); tap(LV_KEY_ESC);
    assert(ui_page==0);
    ui_open(5); settle();
    unsigned games; ui_data_games(&games);
    select_control(control(games+1)); capture("games-last-row");
    tap(LV_KEY_ENTER); assert(ui_game_active() && ui_mode==games-1);
    settle(); capture("game-running");
    tap(LV_KEY_ESC); assert(!ui_game_active() && ui_page==5);
    assert(focus()==control(games+1));
    tap(LV_KEY_ENTER); sim_data_session(UI_APP_GAME,UI_STATE_IDLE,NULL); ui_refresh();
    assert(ui_page==5 && !ui_game_active() && focus()==control(games+1));
    tap(LV_KEY_ESC); assert(ui_page==0);

    ui_tab=1; ui_open(4); settle(); traverse(); capture("renderer-list");
    select_control(control(5)); tap(LV_KEY_ENTER); traverse(); capture("renderer-result");
    tap(LV_KEY_ESC); assert(ui_tab==1 && ui_mode==0);
    tap(LV_KEY_ESC); assert(ui_tab==0 && ui_page==4);
    ui_data_benchmark_start(); tap(LV_KEY_ESC); assert(!ui_data_benchmark_running());
    ui_data_benchmark_start(); lv_tick_inc(8000); ui_refresh(); capture("benchmark-results");
    tap(LV_KEY_ESC); assert(ui_page==0);
    ui_tab=1; ui_open(7); traverse(); capture("coremark-counters");
    tap(LV_KEY_ESC); assert(ui_tab==0 && ui_page==7);
    select_control(control(2)); tap(LV_KEY_ENTER);
    assert(ui_data_session().app==UI_APP_COREMARK);
    lv_tick_inc(6000); ui_refresh(); assert(ui_data_coremark().events[15]>0);
    capture("chip-coremark");
    ui_tab=1; ui_open(8); traverse(); capture("debug-network");
    tap(LV_KEY_ESC); assert(ui_tab==0 && ui_page==8);
    select_control(control(4)); bool hex=ui_data_debug().hex;
    tap(LV_KEY_ENTER); assert(ui_data_debug().hex!=hex);
    select_control(control(5)); tap(LV_KEY_ENTER); tap(LV_KEY_NEXT);
    ui_refresh(); assert(lv_dropdown_get_selected(focus())==1);
    tap(LV_KEY_ENTER); assert(ui_data_debug().baud==921600);
    tap(LV_KEY_NEXT); tap(LV_KEY_ENTER); assert(ui_data_debug().uart_tx==15);
    tap(LV_KEY_NEXT); tap(LV_KEY_ENTER); assert(ui_data_debug().uart_tx==0);
    ui_open(0); ui_monitor_toggle(); traverse(); capture("overlay-home");
    if(ui_monitor_visible()) ui_monitor_toggle();
    ui_open(1); sim_data_session(UI_APP_PIPELINE,UI_STATE_FAILED,"格式错误"); ui_refresh();
    traverse(); capture("session-failed");
    for(unsigned i=0;i<lv_group_get_obj_count(lv_group_get_default());++i)
        if((unsigned)(uintptr_t)lv_obj_get_user_data(control(i))==1002) {
            select_control(control(i)); break;
        }
    tap(LV_KEY_ENTER); assert(ui_data_session().state==UI_STATE_STARTING);
    capture("session-starting");
    sim_data_session(UI_APP_PIPELINE,UI_STATE_STOPPING,NULL);
    ui_refresh(); capture("session-stopping");
    for(unsigned app=0;app<=UI_APP_COREMARK;++app) {
        sim_data_session((ui_app_t)app,UI_STATE_RUNNING,NULL);
        ui_show_app((ui_app_t)app,0);
        assert(ui_data_session().app==(ui_app_t)app);
        assert(ui_page==(app==UI_APP_COREMARK ? 7 : app));
    }
    ui_open(0);
    lv_indev_t *mouse=lv_indev_create(); lv_indev_set_type(mouse,LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(mouse,read_test_input);
    select_control(control(2)); capture("keyboard-focus");
    lv_obj_update_layout(lv_screen_active());
    pointer(mouse,70,220,false); pointer(mouse,70,220,true); pointer(mouse,70,220,false);
    assert(ui_page==1);
    lv_obj_t *button=control(2); lv_area_t a; lv_obj_get_coords(button,&a);
    pointer(mouse,(a.x1+a.x2)/2,(a.y1+a.y2)/2,false);
    assert(lv_obj_has_state(button,LV_STATE_HOVERED));
    pointer(mouse,(a.x1+a.x2)/2,(a.y1+a.y2)/2,true);
    pointer(mouse,(a.x1+a.x2)/2,(a.y1+a.y2)/2,false);
    assert(!lv_obj_has_state(button,LV_STATE_FOCUS_KEY));
    assert(!lv_obj_has_state(button,LV_STATE_PRESSED)); capture("mouse-hover");
    pointer(mouse,55,24,true); pointer(mouse,55,24,false); assert(ui_page==0);
    ui_open(4); ui_data_benchmark_start(); ui_benchmark_controls(true);
    pointer(mouse,55,24,true); pointer(mouse,55,24,false);
    assert(!ui_data_benchmark_running()); ui_benchmark_controls(false);
    lv_indev_delete(mouse);
    lv_indev_t *encoder=lv_indev_create();
    lv_indev_set_type(encoder,LV_INDEV_TYPE_ENCODER);
    lv_indev_set_read_cb(encoder,read_test_input);
    ui_open(1); settle(); select_control(control(2));
    bool before=ui_data_vision().boxes;
    test_input.enc_diff=1; lv_indev_read(encoder); assert(focus()==control(3));
    key_tap(encoder,LV_KEY_ENTER); assert(ui_data_vision().boxes!=before);
    lv_indev_delete(encoder);
    puts("PASS: four-key traversal of all page controls, slider/dropdown edit, switches, "
         "checkboxes, image states, session/retry, game/list focus and layered Esc");
}
static void check_media_hidden(void)
{
    if(!ui_data_vision().boxes) ui_data_boxes();
    for(unsigned page=1;page<=3;++page) {
        ui_open(page); settle();
        for(unsigned i=0;i<lv_group_get_obj_count(lv_group_get_default());++i)
            if((unsigned)(uintptr_t)lv_obj_get_user_data(control(i))==1005) {
                select_control(control(i)); break;
            }
        if(!ui_monitor_visible()) ui_monitor_toggle();
        tap(LV_KEY_ENTER);
        assert(ui_interface_hidden() && !ui_monitor_visible());
        if(page==1) capture("vision-hidden");
        tap(LV_KEY_ESC);
        assert(!ui_interface_hidden() && ui_page==page && ui_monitor_visible());
        tap(LV_KEY_ESC); assert(ui_page==0);
        ui_monitor_toggle();
    }
    ui_open(1); settle();
    lv_indev_t *mouse=lv_indev_create(); lv_indev_set_type(mouse,LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(mouse,read_test_input);
    ui_hide_interface();
    pointer(mouse,55,24,true); pointer(mouse,55,24,false);
    assert(!ui_interface_hidden() && ui_page==1);
    pointer(mouse,55,24,true); pointer(mouse,55,24,false);
    assert(ui_page==0);
    lv_indev_delete(mouse);
    ui_open(1); settle(); sim_data_many_categories(true); ui_refresh();
    ui_vision_t d=ui_data_vision();
    assert(d.count==13 && d.category_used==5 && d.category_id[0]==2 && d.category_id[1]==7);
    capture("vision-categories"); sim_data_many_categories(false);
    ui_open(0); ui_monitor_toggle(); capture("overlay-cpu"); ui_monitor_toggle();
    puts("PASS media hide preserves boxes/overlay setting; "
         "first key/click restores only; top five");
}
int main(void)
{
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    keypad=lv_indev_create(); lv_indev_set_type(keypad,LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(keypad,read_test_input);
    sim_data_init(); ui_start(); capture("home");
    sim_data_toggle_hardware(); ui_open(0); capture("home-vrn");
    sim_data_toggle_hardware();
    const char *names[]={"home","vision","image","process","graphics","games","monitor",
        "chip","debug"};
    for(unsigned page=1;page<=8;++page) {
        if(page==6) continue;
        ui_tab=0; ui_mode=0; ui_open(page); settle(); capture(names[page]);
    }
    check_four_keys(); measure_overlay(); check_media_hidden();
    lv_deinit(); return 0;
}
