/* main_pose_bench.c — T-POSE-GUI host GUI timing and DIRECT repaint coverage.
 * Fixed one/three-person jitter, with incremental/full pixel comparison on removal.
 * Clock domain: scripted LVGL ticks; host monotonic CPU timing.
 */
#define _POSIX_C_SOURCE 200809L
#include "theme.h"
#include "sim_data.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint32_t buffers[2][1280 * 720];
static uint32_t reference[1280 * 720];
static uint32_t *front;
static uint64_t repaint;
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    repaint += (uint64_t)(area->x2 - area->x1 + 1) * (area->y2 - area->y1 + 1);
    front = (uint32_t *)pixels;
    lv_display_flush_ready(display);
}
static uint64_t host_ns(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}
static void update(lv_timer_t *timer) { (void)timer; ui_pose_update(); }
static void step(unsigned count, unsigned frame)
{
    sim_data_pose(count, frame);
    lv_tick_inc(16);
    lv_timer_handler();
}
static void compare_full(unsigned count)
{
    /* Disappearing people must leave the same pixels as a full repaint. */
    step(count, 0);
    memcpy(reference, front, sizeof reference);
    lv_obj_invalidate(lv_screen_active());
    lv_refr_now(NULL);
    assert(memcmp(reference, front, sizeof reference) == 0);
}
static void screenshot(void)
{
    FILE *file = fopen("pose-three.rgb565", "wb");
    if (!file) { perror("pose-three.rgb565"); exit(1); }
    const lv_image_dsc_t *l0 = sim_l0_image();
    for (unsigned y = 0; y < 720; ++y) {
        uint16_t row[1280];
        for (unsigned x = 0; x < 1280; ++x) {
            uint32_t color = sim_composite(l0, front[y * 1280 + x], x, y);
            row[x] = (uint16_t)(((color >> 8) & 0xf800) |
                ((color >> 5) & 0x7e0) | ((color >> 3) & 31));
        }
        if (fwrite(row, sizeof row, 1, file) != 1) { perror("screenshot write"); exit(1); }
    }
    if (fclose(file)) { perror("screenshot close"); exit(1); }
}
int main(void)
{
    lv_init();
    lv_display_t *display = lv_display_create(1280, 720);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display, buffers[0], buffers[1], sizeof buffers[0],
                           LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(display, flush);
    sim_data_init();
    ui_start();
    ui_open(9);
    sim_data_session(UI_APP_POSE, UI_STATE_RUNNING, NULL);
    lv_timer_create(update, 16, NULL);
    for (unsigned count = 1; count <= 3; count += 2) {
        for (unsigned f = 0; f < 12; ++f) step(count, f);
        uint64_t total = 0;
        repaint = 0;
        for (unsigned f = 0; f < 120; ++f) {
            sim_data_pose(count, f);
            lv_tick_inc(16);
            uint64_t start = host_ns();
            lv_timer_handler();
            total += host_ns() - start;
        }
        printf("people=%u frames=120 handler_us=%.2f redraw_pixels=%.2f redraw_pct=%.2f\n",
            count, total / 120000.0, repaint / 120.0, repaint / (120.0 * 1280 * 720) * 100);
    }
    screenshot();
    compare_full(1);
    compare_full(0);
    puts("PASS: incremental repaint equals full repaint after 3->1->0 people");
    lv_deinit();
    return 0;
}
