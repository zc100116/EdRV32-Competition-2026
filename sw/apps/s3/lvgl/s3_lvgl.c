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
#include "mem_xbar.h"
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

/* Scene order is the descriptor order in the locked LVGL v9.6.0 benchmark.
 * Its public API exposes names only in the final summary, so keep labels here;
 * boundaries come from wrapping the benchmark's own scene timer callback.
 */
static const char *const benchmark_names[] = {
    "Empty screen", "Moving wallpaper", "Single rectangle", "Multiple rectangles",
    "Multiple RGB images", "Multiple ARGB images", "Rotated ARGB images", "Multiple labels",
    "Screen sized text", "Multiple arcs", "Containers", "Containers with overlay",
    "Containers with opa", "Containers with opa_layer", "Containers with scrolling", "Widgets demo"
};
struct benchmark_window {
    uint32_t frames;
    uint64_t render_ticks;
    uint64_t sw_ticks;
    uint64_t software;
    struct s3_rnd_measurement draw;
    struct s3_rnd_measurement copy;
    uint64_t xbar_cycles;
    uint64_t xbar[2][5];
    struct s3_rnd_timing timing;
    uint64_t glyph_cpu_ticks;
    struct s3_cpu_counters cpu;
};
static bool benchmark_running;
static bool capturing_scene_timer;
static unsigned benchmark_scene;
static lv_timer_cb_t scene_timer_cb;
static struct s3_draw_rnd_stats benchmark_before;
static struct benchmark_window benchmark_window;
static struct benchmark_window benchmark_total;
static uint64_t refresh_start;
static uint64_t flush_start;
static uint64_t flush_ticks;
static bool frame_rendered;

static void put_u64(uint64_t value)
{
    char digits[21];
    unsigned first = sizeof(digits) - 1;
    digits[first] = 0;
    do {
        digits[--first] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    s3_puts(&digits[first]);
}

/* Three decimal places retain sub-millisecond RND and small per-frame counts. */
static void print_average(const char *name, int64_t value, uint64_t divisor)
{
    s3_puts(" "); s3_puts(name); s3_puts("=");
    if (value < 0) s3_puts("-");
    uint64_t magnitude = value < 0 ? (uint64_t)-value : (uint64_t)value;
    uint64_t fraction = magnitude % divisor * 1000u / divisor;
    put_u64(magnitude / divisor); s3_puts(".");
    if (fraction < 100) s3_puts("0");
    if (fraction < 10) s3_puts("0");
    put_u64(fraction);
}

static void benchmark_print(const char *name, const struct benchmark_window *window)
{
    static const char *const perf_names[] = {
        "perf0_cycles", "perf1_pixels", "perf2_rd_beats", "perf3_wr_beats",
        "perf4_rd_wait_cycles", "perf5_wr_wait_cycles"
    };
    static const char *const xbar_names[] = {
        "rd_txn", "wr_txn", "rd_beats", "wr_beats", "wait_sum_cycles"
    };
    static const char *const cpu_names[] = {
        "cpu_load_use_cycles", "cpu_divide_cycles", "cpu_device_wait_cycles",
        "cpu_frontend_empty_cycles", "cpu_icache_misses", "cpu_dcache_misses",
        "cpu_dirty_writebacks", "cpu_branch_mispredicts"
    };
    uint32_t frames = window->frames;
    uint64_t divisor = (uint64_t)frames * (s3_clock_hz() / 1000u);
    uint64_t rnd_ticks = window->draw.ticks + window->copy.ticks;
    int64_t other = (int64_t)window->render_ticks - (int64_t)rnd_ticks -
                    (int64_t)window->sw_ticks;
    s3_puts("LVGL split scene=\""); s3_puts(name); s3_puts("\" frames=");
    s3_put_u32(frames);
    print_average("render_ms", window->render_ticks, divisor);
    print_average("rnd_ms", rnd_ticks, divisor);
    print_average("sw_ms", window->sw_ticks, divisor);
    print_average("other_ms", other, divisor);
    print_average("doorbells", (uint64_t)window->draw.doorbells + window->copy.doorbells,
                  frames);
    print_average("commands", (uint64_t)window->draw.commands + window->copy.commands,
                  frames);
    print_average("sw_tasks", window->software, frames);
    for (unsigned i = 0; i < 6; ++i)
        print_average(perf_names[i], window->draw.perf[i] + window->copy.perf[i], frames);
    print_average("perf0_ms", window->draw.perf[0] + window->copy.perf[0],
                  (uint64_t)frames * 125000u);
    print_average("draw_rnd_ms", window->draw.ticks, divisor);
    print_average("draw_doorbells", window->draw.doorbells, frames);
    print_average("draw_perf0_cycles", window->draw.perf[0], frames);
    print_average("copy_rnd_ms", window->copy.ticks, divisor);
    print_average("copy_doorbells", window->copy.doorbells, frames);
    print_average("copy_perf0_cycles", window->copy.perf[0], frames);
    print_average("copy_perf0_ms", window->copy.perf[0], (uint64_t)frames * 125000u);
    s3_puts(" xbar_window_cycles="); put_u64(window->xbar_cycles);
    for (unsigned p = 0; p < 2; ++p) {
        for (unsigned i = 0; i < 5; ++i) {
            s3_puts(p == 0 ? " xbar_rnd_p4_" : " xbar_disp_p0_");
            s3_puts(xbar_names[i]); s3_puts("_total=");
            put_u64(window->xbar[p][i]);
        }
    }
    print_average("clean_ms", window->timing.clean_ticks, divisor);
    print_average("wait_ms", window->timing.wait_ticks, divisor);
    print_average("finish_ms", window->timing.finish_ticks, divisor);
    print_average("cache_ops", window->timing.cache_ops, frames);
    print_average("glyph_cpu_ms", window->glyph_cpu_ticks, divisor);
    print_average("cpu_cycles", window->cpu.cycles, frames);
    print_average("cpu_instructions", window->cpu.instructions, frames);
    for (unsigned i = 0; i < 8; ++i)
        print_average(cpu_names[i], window->cpu.events[i], frames);
    /* Host hardware counters are zero; define its ratios as zero as well. */
    print_average("cpu_ipc", window->cpu.instructions,
                  window->cpu.cycles ? window->cpu.cycles : 1u);
    print_average("icache_mpki", window->cpu.events[4] * 1000u,
                  window->cpu.instructions ? window->cpu.instructions : 1u);
    print_average("dcache_mpki", window->cpu.events[5] * 1000u,
                  window->cpu.instructions ? window->cpu.instructions : 1u);
    s3_puts("\r\n");
}

static void benchmark_begin_window(void)
{
    struct mem_xbar_stats discarded;
    benchmark_window = (struct benchmark_window) {0};
    benchmark_before = *s3_draw_rnd_stats();
    /* Exclude UART output between scenes from the next fabric window. */
    mem_xbar_snapshot(&discarded);
    s3_cpu_begin();
}

static void benchmark_finish_window(void)
{
    s3_cpu_end(&benchmark_window.cpu);
    struct mem_xbar_stats fabric;
    mem_xbar_snapshot(&fabric);
    const struct s3_draw_rnd_stats *now = s3_draw_rnd_stats();
    struct benchmark_window *w = &benchmark_window;
    w->draw.ticks = now->rnd_ticks - benchmark_before.rnd_ticks;
    w->draw.commands = now->commands - benchmark_before.commands;
    w->draw.doorbells = now->doorbells - benchmark_before.doorbells;
    w->copy.ticks = now->copy.ticks - benchmark_before.copy.ticks;
    w->copy.commands = now->copy.commands - benchmark_before.copy.commands;
    w->copy.doorbells = now->copy.doorbells - benchmark_before.copy.doorbells;
    w->sw_ticks = now->sw_ticks - benchmark_before.sw_ticks;
    w->software = now->software - benchmark_before.software;
    w->xbar_cycles = fabric.window_cycles;
    w->timing.clean_ticks = now->timing.clean_ticks - benchmark_before.timing.clean_ticks;
    w->timing.wait_ticks = now->timing.wait_ticks - benchmark_before.timing.wait_ticks;
    w->timing.finish_ticks = now->timing.finish_ticks - benchmark_before.timing.finish_ticks;
    w->timing.cache_ops = now->timing.cache_ops - benchmark_before.timing.cache_ops;
    w->glyph_cpu_ticks = now->glyph_cpu_ticks - benchmark_before.glyph_cpu_ticks;
    benchmark_total.timing.clean_ticks += w->timing.clean_ticks;
    benchmark_total.timing.wait_ticks += w->timing.wait_ticks;
    benchmark_total.timing.finish_ticks += w->timing.finish_ticks;
    benchmark_total.timing.cache_ops += w->timing.cache_ops;
    benchmark_total.glyph_cpu_ticks += w->glyph_cpu_ticks;
    benchmark_total.cpu.cycles += w->cpu.cycles;
    benchmark_total.cpu.instructions += w->cpu.instructions;
    for (unsigned i = 0; i < 8; ++i) benchmark_total.cpu.events[i] += w->cpu.events[i];
    for (unsigned i = 0; i < 6; ++i) {
        w->draw.perf[i] = now->perf[i] - benchmark_before.perf[i];
        w->copy.perf[i] = now->copy.perf[i] - benchmark_before.copy.perf[i];
        benchmark_total.draw.perf[i] += w->draw.perf[i];
        benchmark_total.copy.perf[i] += w->copy.perf[i];
    }
    /* SoC 6.4.1: RND P4, DISP P0; physical DDR addresses carry no port number. */
    for (unsigned p = 0; p < 2; ++p) {
        const struct mem_xbar_port_stats *port = &fabric.port[p == 0 ? 4 : 0];
        w->xbar[p][0] = port->rd_txn;
        w->xbar[p][1] = port->wr_txn;
        w->xbar[p][2] = port->rd_beat;
        w->xbar[p][3] = port->wr_beat;
        w->xbar[p][4] = port->wait_sum;
        for (unsigned i = 0; i < 5; ++i) benchmark_total.xbar[p][i] += w->xbar[p][i];
    }
    benchmark_total.frames += w->frames;
    benchmark_total.render_ticks += w->render_ticks;
    benchmark_total.sw_ticks += w->sw_ticks;
    benchmark_total.software += w->software;
    benchmark_total.draw.ticks += w->draw.ticks;
    benchmark_total.draw.commands += w->draw.commands;
    benchmark_total.draw.doorbells += w->draw.doorbells;
    benchmark_total.copy.ticks += w->copy.ticks;
    benchmark_total.copy.commands += w->copy.commands;
    benchmark_total.copy.doorbells += w->copy.doorbells;
    benchmark_total.xbar_cycles += w->xbar_cycles;
    benchmark_print(benchmark_names[benchmark_scene], w);
}

static void benchmark_next_scene(lv_timer_t *timer)
{
    benchmark_finish_window();
    benchmark_scene++;
    benchmark_begin_window();
    scene_timer_cb(timer);
}

lv_timer_t *__real_lv_timer_create(lv_timer_cb_t cb, uint32_t period, void *user_data);

lv_timer_t *__wrap_lv_timer_create(lv_timer_cb_t cb, uint32_t period, void *user_data)
{
    /* During initial Empty screen creation the benchmark creates exactly one
     * timer with the active screen as user_data: next_scene_timer_cb.
     */
    if (capturing_scene_timer && user_data == lv_screen_active()) {
        scene_timer_cb = cb;
        cb = benchmark_next_scene;
        capturing_scene_timer = false;
    }
    return __real_lv_timer_create(cb, period, user_data);
}

static void benchmark_refresh_event(lv_event_t *event)
{
    if (!benchmark_running) return;
    switch (lv_event_get_code(event)) {
    case LV_EVENT_REFR_START:
        refresh_start = s3_ticks();
        flush_ticks = 0;
        frame_rendered = false;
        break;
    case LV_EVENT_RENDER_READY:
        frame_rendered = true;
        break;
    case LV_EVENT_FLUSH_START:
    case LV_EVENT_FLUSH_WAIT_START:
        flush_start = s3_ticks();
        break;
    case LV_EVENT_FLUSH_FINISH:
    case LV_EVENT_FLUSH_WAIT_FINISH:
        flush_ticks += s3_ticks() - flush_start;
        break;
    case LV_EVENT_REFR_READY:
        benchmark_window.render_ticks += s3_ticks() - refresh_start - flush_ticks;
        if (frame_rendered) benchmark_window.frames++;
        break;
    default: break;
    }
}

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
    lv_display_add_event_cb(display, benchmark_refresh_event, LV_EVENT_ALL, NULL);
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
    if (!benchmark_running && elapsed >= 1000) {
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
    if (benchmark_running) {
        struct s3_cpu_counters discarded;
        s3_cpu_end(&discarded);
    }
    benchmark_running = false;
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
    struct s3_cpu_counters discarded;
    s3_cpu_end(&discarded);
    benchmark_running = false;
    benchmark_print("ALL", &benchmark_total);
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
    benchmark_scene = 0;
    benchmark_total = (struct benchmark_window) {0};
    capturing_scene_timer = true;
    lv_demo_benchmark();
    benchmark_begin_window();
    benchmark_running = true;
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
