/* main_shots.c — design P1a §5: headless RGB565 captures; scripted LVGL clock. */
#include "theme.h"
#include "sim_data.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

static uint16_t framebuffer[1280 * 720];
static uint16_t drawbuffer[1280 * 720];

static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const uint16_t *source = (const uint16_t *)pixels;
    for(int y = area->y1; y <= area->y2; ++y)
        for(int x = area->x1; x <= area->x2; ++x)
            framebuffer[y * 1280 + x] = *source++;
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
            if(lv_obj_get_x(o) < 0 || lv_obj_get_y(o) < 0 ||
                lv_obj_get_x(o) + lv_obj_get_width(o) > lv_obj_get_width(parent) ||
                lv_obj_get_y(o) + lv_obj_get_height(o) > lv_obj_get_height(parent)) {
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
    lv_refr_now(NULL);
    check_labels(lv_screen_active());
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

int main(void)
{
    lv_init();
    lv_display_t *display = lv_display_create(1280, 720);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_RGB565);
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
        ui_open(i);
        capture(names[i - 1]);
    }
    ui_tab = 0; ui_open(4); capture("graphics-performance");
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER); capture("graphics-comparison");
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    capture("graphics-layers");
    ui_tab = 0; ui_open(8); capture("debug-uart");
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER); capture("debug-network");
    ui_open(1); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER); capture("vision-boxes-off");
    ui_open(7); ui_key(LV_KEY_ENTER);
    for(unsigned i = 0; i < 12; ++i) { lv_tick_inc(500); lv_timer_handler(); }
    ui_refresh();
    capture("chip-coremark");
    /* Exercise the four-key contract and data actions through real page focus. */
    sim_data_toggle_hardware();
    ui_open(0);
    ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
    assert(ui_page == 0);
    sim_data_toggle_hardware();
    ui_key(LV_KEY_ENTER);
    assert(ui_page == 3);
    for(unsigned i = 1; i < 7; ++i) {
        ui_key(LV_KEY_RIGHT); ui_key(LV_KEY_ENTER);
        assert(ui_mode == i);
    }
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
    for(unsigned i = 0; i < 3; ++i) ui_key(LV_KEY_RIGHT);
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
    ui_key(LV_KEY_ESC); assert(ui_game_open);
    ui_key(LV_KEY_ESC); assert(!ui_game_open && ui_page == 5);
    ui_key(LV_KEY_ESC); assert(ui_page == 0);
    puts("PASS: four-key navigation, availability, page actions, label bounds, 18 captures");
    lv_deinit();
    return 0;
}
