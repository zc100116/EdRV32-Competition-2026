/* File: showcase_lvgl.c
 * Spec: SoC 1.2 S3/7.3/7.4; DISP 5.3; rnd-testplan RN-17.
 * Description: DIRECT double buffering, demo lifecycle and identical-frame comparison.
 * Clock domain: clk_sys; CLINT tick, shared RND/DISP interrupt services.
 */
#include "showcase_lvgl.h"
#include "virtual_input.h"
#include "draw_rnd.h"
#include "../platform.h"
#include "../runtime.h"
#include "../app.h"
#include "virtual_input_uart.h"
#include "cache.h"
#include "mem_xbar.h"
#include "demos/lv_demos.h"

enum { WIDTH = 1280, HEIGHT = 720, STRIDE = WIDTH * 2, PIXELS = WIDTH * HEIGHT };
static _Alignas(4096) uint16_t buffers[2][PIXELS] __attribute__((section(".noinit")));
static lv_display_t *display;
static const uint16_t *front = buffers[1];
static uint32_t input_snapshot;
static uint32_t flush_count;
static bool demo_running;
static lv_timer_t *framework_timers[32];
static unsigned framework_timer_count;

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
    struct showcase_rnd_measurement draw;
    struct showcase_rnd_measurement copy;
    uint64_t xbar_cycles;
    uint64_t xbar[2][5];
    struct showcase_rnd_timing timing;
    uint64_t glyph_cpu_ticks;
    struct showcase_cpu_counters cpu;
};
static bool benchmark_running;
static bool capturing_scene_timer;
static unsigned benchmark_scene;
static lv_timer_cb_t scene_timer_cb;
static struct showcase_draw_rnd_stats benchmark_before;
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
    platform_puts(&digits[first]);
}

/* Three decimal places retain sub-millisecond RND and small per-frame counts. */
static void print_average(const char *name, int64_t value, uint64_t divisor)
{
    platform_puts(" "); platform_puts(name); platform_puts("=");
    if (value < 0) platform_puts("-");
    uint64_t magnitude = value < 0 ? (uint64_t)-value : (uint64_t)value;
    uint64_t fraction = magnitude % divisor * 1000u / divisor;
    put_u64(magnitude / divisor); platform_puts(".");
    if (fraction < 100) platform_puts("0");
    if (fraction < 10) platform_puts("0");
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
    uint64_t divisor = (uint64_t)frames * (platform_clock_hz() / 1000u);
    uint64_t rnd_ticks = window->draw.ticks + window->copy.ticks;
    int64_t other = (int64_t)window->render_ticks - (int64_t)rnd_ticks -
                    (int64_t)window->sw_ticks;
    platform_puts("LVGL split scene=\""); platform_puts(name); platform_puts("\" frames=");
    platform_put_u32(frames);
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
    platform_puts(" xbar_window_cycles="); put_u64(window->xbar_cycles);
    for (unsigned p = 0; p < 2; ++p) {
        for (unsigned i = 0; i < 5; ++i) {
            platform_puts(p == 0 ? " xbar_rnd_p4_" : " xbar_disp_p0_");
            platform_puts(xbar_names[i]); platform_puts("_total=");
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
    platform_puts("\r\n");
}

static void benchmark_begin_window(void)
{
    struct mem_xbar_stats discarded;
    benchmark_window = (struct benchmark_window) {0};
    benchmark_before = *showcase_draw_rnd_stats();
    /* Exclude UART output between scenes from the next fabric window. */
    mem_xbar_snapshot(&discarded);
    showcase_cpu_begin();
}

static void benchmark_finish_window(void)
{
    showcase_cpu_end(&benchmark_window.cpu);
    struct mem_xbar_stats fabric;
    mem_xbar_snapshot(&fabric);
    const struct showcase_draw_rnd_stats *now = showcase_draw_rnd_stats();
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
        refresh_start = platform_ticks();
        flush_ticks = 0;
        frame_rendered = false;
        break;
    case LV_EVENT_RENDER_READY:
        frame_rendered = true;
        break;
    case LV_EVENT_FLUSH_START:
    case LV_EVENT_FLUSH_WAIT_START:
        flush_start = platform_ticks();
        break;
    case LV_EVENT_FLUSH_FINISH:
    case LV_EVENT_FLUSH_WAIT_FINISH:
        flush_ticks += platform_ticks() - flush_start;
        break;
    case LV_EVENT_REFR_READY:
        benchmark_window.render_ticks += platform_ticks() - refresh_start - flush_ticks;
        if (frame_rendered) benchmark_window.frames++;
        break;
    default: break;
    }
}

static uint32_t tick(void)
{
    return platform_milliseconds();
}

static void log_message(lv_log_level_t level, const char *text)
{
    (void)level;
    platform_puts(text);
}

static uint32_t dirty_bytes;
static bool clean_all_needed;
static volatile bool flush_pending;
static volatile bool scan_started;
static const uint16_t *pending_pixels;
static volatile uint32_t display_events;

static void flush(lv_display_t *disp, const lv_area_t *area, uint8_t *pixels)
{
    uint32_t bytes = (uint32_t)(area->x2 - area->x1 + 1) * 2u;
    uint32_t covered = (((uint32_t)area->x2 * 2u + 33u) & ~31u) -
                       (((uint32_t)area->x1 * 2u) & ~31u);
    dirty_bytes += covered * (uint32_t)(area->y2 - area->y1 + 1);
    if (dirty_bytes > 32768u) clean_all_needed = true;
    if (!clean_all_needed) {
        for (int32_t y = area->y1; y <= area->y2; ++y)
            cache_clean((uintptr_t)pixels + (uint32_t)y * STRIDE +
                        (uint32_t)area->x1 * 2u, bytes);
    }
    if (lv_display_flush_is_last(disp)) {
        if (clean_all_needed) cache_clean_all();
        pending_pixels = (const uint16_t *)pixels;
        flush_pending = true;
        dirty_bytes = 0;
        clean_all_needed = false;
        /* Stride and geometry stay fixed; only the next base changes. The
         * SWITCH IRQ releases front and resumes this asynchronous flush. */
        mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET,
                     rnd_physical(pending_pixels));
    } else lv_display_flush_ready(disp);
}
void showcase_gui_disp_event(uint32_t irq)
{
    if (!scan_started && (irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) {
        scan_started = true;
        sched_signal(&gui_task, 1);
    }
    if (!flush_pending || !(irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK)) return;
    display_events |= irq;
    sched_signal(&gui_task, 1);
}
static void sync_buffers(lv_display_t *disp, const lv_area_t *area)
{
    void *offscreen = lv_display_get_buf_active(disp)->data;
    showcase_draw_rnd_copy(offscreen, front, STRIDE, area);
    lv_display_sync_ready(disp);
}

static void read_keys(lv_indev_t *indev, lv_indev_data_t *data)
{
    (void)indev;
    if (showcase_launcher_active()) {
        data->state = LV_INDEV_STATE_RELEASED;
        return;
    }
    uint32_t keys = input_snapshot;
    uint16_t virtual_keys = platform_virtual_input().keys;
    static const uint32_t lv_keys[] = {
        LV_KEY_UP, LV_KEY_DOWN, LV_KEY_LEFT, LV_KEY_RIGHT,
        LV_KEY_ENTER, LV_KEY_ESC, LV_KEY_NEXT, LV_KEY_PREV
    };
    static const uint16_t bits[] = {
        VI_UP, VI_DOWN, VI_LEFT, VI_RIGHT, VI_ENTER, VI_ESC, VI_NEXT, VI_PREV
    };
    data->state = LV_INDEV_STATE_PRESSED;
    for (unsigned i = 0; i < 8; ++i) {
        if (virtual_keys & bits[i]) {
            data->key = lv_keys[i];
            return;
        }
    }
    data->state = keys ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    if (keys & PLATFORM_LEFT) data->key = LV_KEY_PREV;
    else if (keys & PLATFORM_RIGHT) data->key = LV_KEY_NEXT;
    else if (keys & PLATFORM_ENTER) data->key = LV_KEY_ENTER;
    else if (keys & PLATFORM_BACK) data->key = LV_KEY_ESC;
}

static lv_obj_t *pointer_cursor;

static void read_pointer(lv_indev_t *indev, lv_indev_data_t *data)
{
    (void)indev;
    struct virtual_input_state input = platform_virtual_input();
    data->point.x = input.x;
    data->point.y = input.y;
    data->state = (input.mouse & 1) ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    if (input.active) lv_obj_set_hidden(pointer_cursor, false);
}

void showcase_lvgl_init(void)
{
    lv_init();
    lv_log_register_print_cb(log_message);
    lv_tick_set_cb(tick);
    showcase_draw_rnd_init();
    showcase_draw_rnd_enable((platform_hardware() & APP_HW_RND) != 0);
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
    lv_indev_t *pointer = lv_indev_create();
    lv_indev_set_type(pointer, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(pointer, read_pointer);
    static const lv_point_precise_t arrow[] = {
        {0, 0}, {0, 18}, {5, 13}, {10, 23}, {14, 21}, {9, 11}, {17, 11}, {0, 0}
    };
    pointer_cursor = lv_line_create(lv_layer_sys());
    lv_line_set_points(pointer_cursor, arrow, sizeof(arrow) / sizeof(arrow[0]));
    lv_obj_set_style_line_color(pointer_cursor, lv_color_hex(0xffffff), 0);
    lv_obj_set_style_line_width(pointer_cursor, 2, 0);
    lv_obj_set_clickable(pointer_cursor, false);
    lv_obj_set_hidden(pointer_cursor, true);
    lv_indev_set_cursor(pointer, pointer_cursor);
    lv_memzero((void *)front, sizeof(buffers[0]));
    showcase_gui_restore();
    platform_puts("LVGL v9.6.0 DIRECT RGB565 1280x720 batch=32\r\n");
}

uint32_t showcase_gui_frames(void) { return flush_count; }
void showcase_gui_step(struct sched_task *task)
{
    sched_take(task);
    if (showcase_gui_paused() || !scan_started) return;
    uint32_t state = virtual_input_lock();
    uint32_t events = display_events;
    display_events = 0;
    virtual_input_unlock(state);
    if (flush_pending) {
        if (events & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) {
            front = pending_pixels;
            flush_pending = false;
            ++flush_count;
            if (flush_count == 1) platform_puts("showcase first frame\r\n");
            lv_display_flush_ready(display);
        }
        if (flush_pending) return;
    }
    uint32_t delay = lv_timer_handler();
    if (!flush_pending && delay != LV_NO_TIMER_READY)
        sched_wake_at(task, platform_ticks() +
                      (uint64_t)delay * (platform_clock_hz() / 1000u));
}
void showcase_gui_restore(void)
{
    /* The caller already observed stopped DISP/RND. Clean with IRQs enabled;
     * only completion acknowledgement and the new scan setup are atomic. */
    cache_clean_all();
    uint32_t state = virtual_input_lock();
    engine_irq_clear(ENGINE_DISP, EDRV32_DISP_IRQ_STAT_FRAME_MASK |
        EDRV32_DISP_IRQ_STAT_SWITCH_MASK | EDRV32_DISP_IRQ_STAT_SWITCH1_MASK);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET,
                 EDRV32_RND_IRQ_STAT_DONE_MASK);
    platform_media_callbacks(NULL, NULL, NULL);
    /* LVGL already swapped its draw buffer when flush returned. On a stopped
     * scan, the complete pending image becomes front even without SWITCH. */
    if (flush_pending) front = pending_pixels;
    flush_pending = false;
    /* First enabled FRAME has no SWITCH; establish front before drawing back. */
    scan_started = false;
    display_events = 0;
    disp_l0_scroll(0, 0);
    disp_layer_enable(DISP_L1, 0);
    disp_submit(DISP_L0, rnd_physical(front), STRIDE);
    disp_layer_enable(DISP_L0, 1);
    engine_control(ENGINE_DISP, EDRV32_DISP_CTRL_ENABLE_MASK);
    virtual_input_unlock(state);
    lv_display_flush_ready(display);
    lv_obj_invalidate(lv_screen_active());
    lv_obj_invalidate(lv_layer_top());
    lv_obj_invalidate(lv_layer_sys());
    sched_signal(&gui_task, 1);
}

static void begin_demo(void)
{
    showcase_lvgl_stop_demo();
    framework_timer_count = 0;
    for (lv_timer_t *t = lv_timer_get_next(NULL); t; t = lv_timer_get_next(t))
        framework_timers[framework_timer_count++] = t;
    demo_running = true;
}

void showcase_lvgl_stop_demo(void)
{
    if (benchmark_running) {
        struct showcase_cpu_counters discarded;
        showcase_cpu_end(&discarded);
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

void showcase_lvgl_start_widgets(void)
{
    begin_demo();
    lv_demo_widgets();
}

static void benchmark_end(const lv_demo_benchmark_summary_t *summary)
{
    struct showcase_cpu_counters discarded;
    showcase_cpu_end(&discarded);
    benchmark_running = false;
    benchmark_print("ALL", &benchmark_total);
    for (unsigned i = 0; summary->scenes[i].create_cb; ++i) {
        const lv_demo_benchmark_scene_dsc_t *s = &summary->scenes[i];
        platform_puts("LVGL benchmark scene="); platform_puts(s->name);
        platform_puts(" fps=");
        platform_put_u32(s->measurement_cnt ? s->fps_avg / s->measurement_cnt : 0);
        platform_puts("\r\n");
    }
    platform_puts("LVGL benchmark average fps=");
    platform_put_u32(summary->valid_scene_cnt ?
        summary->total_avg_fps / summary->valid_scene_cnt : 0);
    platform_puts("\r\n");
    showcase_draw_rnd_print_stats();
    lv_demo_benchmark_summary_display(summary);
}

void showcase_lvgl_start_benchmark(void)
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

void showcase_lvgl_input(uint32_t keys) { input_snapshot = keys; }
lv_display_t *showcase_lvgl_display(void) { return display; }
