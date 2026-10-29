/* File: s3_lvgl.c
 * Spec: SoC 1.2 S3/7.3/7.4; DISP 5.3; rnd-testplan RN-17.
 * Description: DIRECT double buffering, demo lifecycle and identical-frame comparison.
 * Clock domain: clk_sys; CLINT tick, shared RND/DISP interrupt services.
 */
#include "s3_lvgl.h"
#include "draw_rnd.h"
#include "rn17_compare.h"
#include "../s3_platform.h"
#include "cache.h"
#include "demos/lv_demos.h"

enum { WIDTH = 1280, HEIGHT = 720, STRIDE = WIDTH * 2, PIXELS = WIDTH * HEIGHT };
static _Alignas(4096) uint16_t buffers[2][PIXELS];
static _Alignas(64) uint16_t reference[PIXELS];
static lv_display_t *display;
static const uint16_t *front = buffers[1];
static bool comparing;
static uint32_t input_snapshot;
static uint32_t frozen_tick;
static uint32_t flush_count;
static uint32_t report_tick;
static uint32_t report_frames;
static uint32_t report_rnd;
static uint32_t report_sw;
static bool demo_running;
static lv_timer_t *framework_timers[32];
static unsigned framework_timer_count;
static struct s3_lvgl_comparison comparison;

static uint32_t tick(void)
{
    return comparing ? frozen_tick : s3_milliseconds();
}

static void log_message(lv_log_level_t level, const char *text)
{
    (void)level;
    s3_puts(text);
}

static void flush(lv_display_t *disp, const lv_area_t *area, uint8_t *pixels)
{
    (void)area;
    if (lv_display_flush_is_last(disp)) {
        cache_clean((uintptr_t)pixels, sizeof(buffers[0]));
        if (!comparing) s3_display_present(pixels, STRIDE, NULL, 0);
        front = (const uint16_t *)pixels;
        flush_count++;
    }
    lv_display_flush_ready(disp);
}

static void sync_buffers(lv_display_t *disp, const lv_area_t *area)
{
    void *offscreen = lv_display_get_buf_active(disp)->data;
    s3_draw_rnd_copy(offscreen, front, STRIDE, area);
    lv_display_sync_ready(disp);
}

static void read_keys(lv_indev_t *indev, lv_indev_data_t *data)
{
    (void)indev;
    uint32_t keys = input_snapshot;
    data->state = keys ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    if (keys & S3_KEY_LEFT) data->key = LV_KEY_PREV;
    else if (keys & S3_KEY_RIGHT) data->key = LV_KEY_NEXT;
    else if (keys & S3_KEY_JUMP) data->key = LV_KEY_ENTER;
    else if (keys & S3_KEY_PAUSE) data->key = LV_KEY_ESC;
}

void s3_lvgl_init(void)
{
    lv_init();
    lv_log_register_print_cb(log_message);
    lv_tick_set_cb(tick);
    s3_draw_rnd_init();
    display = lv_display_create(WIDTH, HEIGHT);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(display, buffers[0], buffers[1], sizeof(buffers[0]),
                           LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(display, flush);
    lv_display_set_sync_cb(display, sync_buffers);
    lv_group_t *group = lv_group_create();
    lv_group_set_default(group);
    lv_indev_t *keys = lv_indev_create();
    lv_indev_set_type(keys, LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(keys, read_keys);
    lv_indev_set_group(keys, group);
    cache_clean((uintptr_t)front, sizeof(buffers[0]));
    s3_display_begin(front, STRIDE, NULL, 0);
    report_tick = tick();
    s3_puts("LVGL v9.6.0 DIRECT RGB565 1280x720 batch=32\r\n");
}

void s3_lvgl_step(void)
{
    lv_timer_handler();
    uint32_t now = tick();
    uint32_t elapsed = now - report_tick;
    if (elapsed >= 1000) {
        const struct s3_draw_rnd_stats *s = s3_draw_rnd_stats();
        s3_puts("LVGL fps=");
        s3_put_u32((flush_count - report_frames) * 1000u / elapsed);
        s3_puts(" rnd_tasks="); s3_put_u32(s->executed - report_rnd);
        s3_puts(" sw_tasks="); s3_put_u32(s->software - report_sw);
        s3_puts("\r\n");
        report_tick = now;
        report_frames = flush_count;
        report_rnd = s->executed;
        report_sw = s->software;
    }
}

static void invalidate_all(void)
{
    lv_obj_invalidate(lv_screen_active());
    lv_obj_invalidate(lv_layer_top());
    lv_obj_invalidate(lv_layer_sys());
}

void s3_lvgl_restore_display(void)
{
    cache_clean((uintptr_t)front, sizeof(buffers[0]));
    s3_display_begin(front, STRIDE, NULL, 0);
    invalidate_all();
    lv_refr_now(display);
}

static void begin_demo(void)
{
    s3_lvgl_stop_demo();
    framework_timer_count = 0;
    for (lv_timer_t *t = lv_timer_get_next(NULL); t; t = lv_timer_get_next(t))
        framework_timers[framework_timer_count++] = t;
    demo_running = true;
}

void s3_lvgl_stop_demo(void)
{
    /* Widget destructors delete their own timers. Delete the object tree first,
     * then remove remaining demo timers such as benchmark's scene timer.
     */
    lv_obj_clean(lv_screen_active());
    lv_obj_remove_style_all(lv_screen_active());
    lv_obj_clean(lv_layer_top());
    if (demo_running) {
        lv_timer_t *t = lv_timer_get_next(NULL);
        while (t) {
            lv_timer_t *next = lv_timer_get_next(t);
            bool framework = false;
            for (unsigned i = 0; i < framework_timer_count; ++i)
                if (framework_timers[i] == t) framework = true;
            if (!framework) lv_timer_delete(t);
            t = next;
        }
        lv_anim_delete_all();
        demo_running = false;
    }
}

void s3_lvgl_start_widgets(void)
{
    begin_demo();
    lv_demo_widgets();
}

static void benchmark_end(const lv_demo_benchmark_summary_t *summary)
{
    for (unsigned i = 0; summary->scenes[i].create_cb; ++i) {
        const lv_demo_benchmark_scene_dsc_t *s = &summary->scenes[i];
        s3_puts("LVGL benchmark scene="); s3_puts(s->name);
        s3_puts(" fps=");
        s3_put_u32(s->measurement_cnt ? s->fps_avg / s->measurement_cnt : 0);
        s3_puts("\r\n");
    }
    s3_puts("LVGL benchmark average fps=");
    s3_put_u32(summary->valid_scene_cnt ?
        summary->total_avg_fps / summary->valid_scene_cnt : 0);
    s3_puts("\r\n");
    s3_draw_rnd_print_stats();
    lv_demo_benchmark_summary_display(summary);
}

void s3_lvgl_start_benchmark(void)
{
    begin_demo();
    lv_demo_benchmark_set_end_cb(benchmark_end);
    lv_demo_benchmark();
}

void s3_lvgl_self_compare(void)
{
    bool was_enabled = s3_draw_rnd_enabled();
    s3_display_stop();
    frozen_tick = s3_milliseconds();
    comparing = true;
    s3_compare_begin();
    s3_draw_rnd_enable(false);
    invalidate_all();
    lv_refr_now(display);
    lv_memcpy(reference, front, sizeof(reference));
    struct s3_draw_rnd_stats before = *s3_draw_rnd_stats();
    s3_draw_rnd_enable(true);
    invalidate_all();
    lv_refr_now(display);
    s3_compare_pixels(&comparison, reference, front, PIXELS);
    const struct s3_draw_rnd_stats *after = s3_draw_rnd_stats();
    comparison.rnd_tasks = after->executed - before.executed;
    comparison.sw_tasks = after->software - before.software;
    s3_puts("RN-17 full_max_lsb="); s3_put_u32(comparison.full_max_lsb);
    s3_puts(" edge_max_lsb="); s3_put_u32(comparison.edge_max_lsb);
    s3_puts(" over1="); s3_put_u32(comparison.over1);
    s3_puts(" pixels="); s3_put_u32(PIXELS);
    s3_puts(" over1_ppm="); s3_put_u32(comparison.over1 * 1000000ull / PIXELS);
    s3_puts(" bins_0_1_2_3to4_5plus=");
    for (unsigned i = 0; i < 5; ++i) {
        s3_put_u32(comparison.histogram[i]); s3_puts(i == 4 ? "" : ",");
    }
    s3_puts(" rnd_tasks="); s3_put_u32(comparison.rnd_tasks);
    s3_puts(" sw_tasks="); s3_put_u32(comparison.sw_tasks);
    s3_puts(s3_compare_passes(&comparison) ? " PASS" : " FAIL");
    s3_puts("\r\n");
    s3_compare_end();
    s3_draw_rnd_print_stats();
    for (unsigned i = 1; i < S3_RND_TASK_TYPES; ++i) {
        if (after->claimed[i] != before.claimed[i] ||
            after->unclaimed[i] != before.unclaimed[i]) {
            s3_puts("RN-17 type="); s3_put_u32(i);
            s3_puts(" claimed="); s3_put_u32(after->claimed[i] - before.claimed[i]);
            s3_puts(" unclaimed="); s3_put_u32(after->unclaimed[i] - before.unclaimed[i]);
            s3_puts("\r\n");
        }
    }
    s3_draw_rnd_enable(was_enabled);
    comparing = false;
    cache_clean((uintptr_t)front, sizeof(buffers[0]));
    s3_display_begin(front, STRIDE, NULL, 0);
    report_tick = tick();
    report_frames = flush_count;
    report_rnd = after->executed;
    report_sw = after->software;
}

void s3_lvgl_set_rnd(bool value) { s3_draw_rnd_enable(value); }
void s3_lvgl_input(uint32_t keys) { input_snapshot = keys; }
lv_display_t *s3_lvgl_display(void) { return display; }
const struct s3_lvgl_comparison *s3_lvgl_comparison(void) { return &comparison; }
const uint16_t *s3_lvgl_reference_pixels(void) { return reference; }
const uint16_t *s3_lvgl_rendered_pixels(void) { return front; }
