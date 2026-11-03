/* main_shots.c — design P1a §5: headless RGB565 captures; scripted LVGL clock. */
#include "style_samples.h"
#include <stdio.h>
#include <stdlib.h>

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

static void capture(const char *name)
{
    lv_refr_now(NULL);
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
    samples_start();
    for(unsigned style = 0; style < 3; ++style) {
        char name[32];
        samples_state(style, false, 0);
        snprintf(name, sizeof(name), "%c-home", 'A' + (int)style);
        capture(name);
        if(style == 0) {
            samples_key(LV_KEY_RIGHT);
            capture("A-home-focus");
        }
        for(unsigned i = style == 0 ? 1 : 0; i < 5; ++i) samples_key(LV_KEY_RIGHT);
        samples_key(LV_KEY_ENTER);
        lv_tick_inc(500);
        lv_timer_handler();
        snprintf(name, sizeof(name), "%c-monitor", 'A' + (int)style);
        capture(name);
    }
    lv_deinit();
    return 0;
}
