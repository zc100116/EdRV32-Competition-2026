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
static void check_input_devices(void)
{
    lv_indev_t *keypad=lv_indev_create();
    lv_indev_set_type(keypad,LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(keypad,read_test_input);
    lv_indev_t *encoder=lv_indev_create();
    lv_indev_set_type(encoder,LV_INDEV_TYPE_ENCODER);
    lv_indev_set_read_cb(encoder,read_test_input);
    ui_open(1);
    bool paused=ui_data_vision(false).paused;
    key_tap(keypad,LV_KEY_ENTER); assert(ui_data_vision(false).paused!=paused);
    key_tap(keypad,LV_KEY_NEXT);
    bool boxes=ui_data_vision(false).boxes;
    key_tap(keypad,LV_KEY_ENTER); assert(ui_data_vision(false).boxes!=boxes);
    test_input.enc_diff=-1; lv_indev_read(encoder);
    key_tap(encoder,LV_KEY_ENTER); assert(ui_data_vision(false).paused==paused);
    key_tap(keypad,LV_KEY_ESC); assert(ui_page==0);
    ui_open(6); key_tap(keypad,LV_KEY_ESC); assert(ui_page==0);
    assert(ui_monitor_visible()); ui_monitor_toggle();
    ui_open(5); key_tap(keypad,LV_KEY_ENTER); assert(ui_game_open);
    key_tap(keypad,LV_KEY_ESC); assert(!ui_game_open && ui_page==5);
    ui_open(1); key_tap(keypad,LV_KEY_NEXT); key_tap(keypad,LV_KEY_NEXT);
    key_tap(keypad,LV_KEY_ENTER); assert(ui_detection_settings);
    key_tap(keypad,LV_KEY_ENTER); assert(ui_data_detection_config().threshold==45);
    key_tap(keypad,LV_KEY_NEXT); key_tap(keypad,LV_KEY_ENTER);
    assert(ui_data_detection_config().threshold==50);
    key_tap(keypad,LV_KEY_NEXT); key_tap(keypad,LV_KEY_NEXT);
    key_tap(keypad,LV_KEY_ENTER); assert(!ui_data_detection_config().classes[0]);
    test_input.enc_diff=80; lv_indev_read(encoder);
    key_tap(encoder,LV_KEY_ENTER);
    assert(ui_data_detection_config().classes[2]==(1u<<15));
    lv_indev_t *pointer=lv_indev_create();
    lv_indev_set_type(pointer,LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(pointer,read_test_input); lv_obj_update_layout(lv_screen_active());
    test_input.point=(lv_point_t){920,186};
    test_input.state=LV_INDEV_STATE_PRESSED; lv_indev_read(pointer);
    test_input.state=LV_INDEV_STATE_RELEASED; lv_indev_read(pointer);
    assert(ui_data_detection_config().classes[0]==UINT32_MAX);
    key_tap(keypad,LV_KEY_ESC); assert(!ui_detection_settings && ui_page==1);
    lv_obj_update_layout(lv_screen_active());
    test_input.point=(lv_point_t){55,24};
    test_input.state=LV_INDEV_STATE_PRESSED; lv_indev_read(pointer);
    test_input.state=LV_INDEV_STATE_RELEASED; lv_indev_read(pointer);
    assert(ui_page==0);
    ui_tab=0; ui_open(4); ui_data_benchmark_start(); lv_tick_inc(1000);
    unsigned completed=ui_data_benchmark_progress();
    ui_benchmark_controls(true); lv_obj_update_layout(lv_layer_sys());
    test_input.point=(lv_point_t){55,24};
    test_input.state=LV_INDEV_STATE_PRESSED; lv_indev_read(pointer);
    test_input.state=LV_INDEV_STATE_RELEASED; lv_indev_read(pointer);
    assert(!ui_data_benchmark_running() && ui_data_benchmark_progress()==completed);
    ui_benchmark_controls(false);
    lv_indev_delete(pointer);
    lv_indev_delete(keypad); lv_indev_delete(encoder);
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
int main(void)
{
    lv_init();
    lv_display_t *display = lv_display_create(1280, 720);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display, drawbuffer, NULL, sizeof(drawbuffer),
                           LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display, flush);
    sim_data_init();
    ui_start();
    capture("home");
    sim_data_toggle_hardware();
    ui_open(0);
    capture("home-vrn");
    sim_data_toggle_hardware();
    ui_open(0);
    for(unsigned i = 0; i < 5; ++i) ui_key(LV_KEY_RIGHT);
    capture("home-focus-6");
    const char *names[] = {"vision", "image", "process", "graphics", "games", "monitor",
        "chip", "debug"};
    lv_tick_inc(500);
    lv_timer_handler();
    for(unsigned i = 1; i <= 8; ++i) {
        ui_tab = 0;
        if(i==6) continue;
        ui_open(i);
        if (i != 3) capture(names[i - 1]);
    }
    ui_open(3); ui_process_action(0); capture("process-collapsed");
    ui_process_action(0); capture("process");
    unsigned game_count;
    const ui_game_t *games = ui_data_games(&game_count);
    assert(game_count == 30);
    assert(lv_strcmp(games[0].name, "超级马里奥") == 0);
    assert(lv_strcmp(games[29].name, "中国象棋") == 0);
    ui_open(5);
    for(unsigned i = 1; i < game_count; ++i) ui_key(LV_KEY_RIGHT);
    capture("games-last-row");
    lv_obj_t *grid = lv_obj_get_child(lv_obj_get_child(lv_screen_active(), -1), -1);
    lv_obj_t *last_game = lv_obj_get_child(grid, 29);
    lv_area_t viewport, selected;
    lv_obj_get_coords(grid, &viewport);
    lv_obj_get_coords(last_game, &selected);
    assert(lv_obj_has_state(last_game, LV_STATE_FOCUSED));
    assert(selected.y1 >= viewport.y1 && selected.y2 <= viewport.y2);
    assert(lv_obj_get_scroll_y(grid) > 0);
    ui_key(LV_KEY_ENTER);
    assert(ui_game_open && ui_mode == 29);
    ui_key(LV_KEY_ESC);
    assert(!ui_game_open && ui_page == 5);
    grid = lv_obj_get_child(lv_obj_get_child(lv_screen_active(), -1), -1);
    assert(lv_obj_has_state(lv_obj_get_child(grid, 29), LV_STATE_FOCUSED));
    ui_tab=0; ui_open(4); capture("graphics-performance");
    ui_data_benchmark_start(); lv_tick_inc(8000); ui_open(4); capture("benchmark-results");
    ui_data_render_start(RENDER_TEST_COUNT);
    for(unsigned i=0;i<TEST_LAYERS;++i) assert(ui_data_render_results()[i].complete);
    ui_graphics_action(1); capture("renderer-list");
    ui_graphics_action(10+TEST_GRAD_H); capture("renderer-result");
    ui_key(LV_KEY_ESC); assert(ui_tab==1 && ui_mode==0);
    ui_key(LV_KEY_ESC); assert(ui_tab==0 && ui_page==4);
    ui_key(LV_KEY_ESC); assert(ui_page==0);
    ui_monitor_toggle(); capture("overlay-home");
    ui_open(5); capture("overlay-games");
    for(unsigned corner=0;corner<4;++corner) {
        int x,y; ui_monitor_position(&x,&y);
        assert(x==((corner&1) ? 960 : 0) && y==((corner&2) ? 480 : 0));
        ui_monitor_corner();
    }
    ui_monitor_toggle();
    ui_tab = 0; ui_open(8); capture("debug-uart"); capture("page-back");
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER); capture("debug-network");
    ui_open(1); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER); capture("vision-boxes-off");
    ui_tab=0; ui_open(7); ui_key(LV_KEY_ENTER);
    for(unsigned i = 0; i < 12; ++i) { lv_tick_inc(500); lv_timer_handler(); }
    ui_refresh();
    assert(ui_data_coremark().cycles[0]>0 && ui_data_coremark().events[15]>0);
    capture("chip-coremark");
    ui_tab=1; ui_open(7); capture("coremark-counters");
    ui_key(LV_KEY_ESC); assert(ui_tab==0 && ui_page==7);
    ui_open(1); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_detection_settings); capture("detection-settings");
    ui_key(LV_KEY_ESC); assert(!ui_detection_settings && ui_page==1);
    bool saved_boxes=ui_data_vision(false).boxes;
    if(!saved_boxes) ui_data_boxes();
    ui_data_detection_threshold(70); ui_data_detection_all(false);
    ui_data_detection_class(0,true); ui_data_detection_class(2,true);
    ui_refresh(); assert(ui_data_vision(false).count==3); capture("vision-filtered");
    ui_data_detection_threshold(50); ui_data_detection_all(true);
    if(!saved_boxes) ui_data_boxes();
    /* Exercise the four-key contract and data actions through real page focus. */
    sim_data_toggle_hardware();
    ui_open(0);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_page == 0);
    sim_data_toggle_hardware();
    ui_key(LV_KEY_ENTER);
    assert(ui_page == 3);
    ui_process_action(11);
    assert(ui_data_process_config().brightness == 1);
    ui_process_action(2);
    assert(ui_data_process_config().brightness == 0);
    ui_open(1); ui_key(LV_KEY_ENTER);
    assert(ui_data_vision(false).paused);
    ui_key(LV_KEY_ENTER);
    assert(!ui_data_vision(false).paused);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_data_vision(false).boxes);
    ui_open(2); ui_key(LV_KEY_ENTER);
    assert(ui_data_vision(true).waiting);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_page == 1);
    ui_tab = 0; ui_open(4);
    for(unsigned i = 0; i < 2; ++i) ui_key(LV_KEY_RIGHT);
    ui_key(LV_KEY_ENTER);
    lv_tick_inc(8000); ui_refresh();
    assert(ui_data_benchmark_progress() == 16);
    ui_tab = 0; ui_open(8);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_data_debug().hex);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_data_debug().baud == 921600);
    ui_key(LV_KEY_ENTER); assert(ui_data_debug().baud == 2000000);
    ui_key(LV_KEY_ENTER); assert(ui_data_debug().baud == 115200);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_data_debug().uart_tx == 15);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_data_debug().uart_tx == 0 && ui_data_debug().uart_rx == 0);
    ui_tab = 1; ui_open(8);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_data_debug().echo_count == 10);
    ui_open(5); ui_key(LV_KEY_ENTER);
    assert(ui_game_open);
    ui_key(LV_KEY_ESC); assert(!ui_game_open && ui_page == 5);
    ui_key(LV_KEY_ESC); assert(ui_page == 0);
    check_input_devices();
    puts("PASS: game/list/home focus restoration, mouse back/benchmark stop, "
         "keypad/encoder, four-key navigation, availability, page actions, "
         "label bounds, detection settings and filtering");
    measure_overlay();
    lv_deinit();
    return 0;
}
